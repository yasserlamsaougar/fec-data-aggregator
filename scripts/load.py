#!/usr/bin/env python3
"""
FEC Raw File Loader
-------------------
Reads extracted FEC pipe-delimited files and loads them into DuckDB
under the `raw` schema, ready for DBT to transform.

Run this after scripts/download.py --extract

Usage:
    python scripts/load.py
    python scripts/load.py --cycles 2024 2022
    python scripts/load.py --cycles 2024 --db data/fec.duckdb
"""

import argparse
import logging
from pathlib import Path

import duckdb

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

ALL_CYCLES = list(range(1980, 2025, 2))

# FEC file specs: columns in exact order as published.
# Pipe-delimited, no header row in data files.
# Source: https://www.fec.gov/campaign-finance-data/about-campaign-finance-data/bulk-data-formats/
FILE_SPECS: dict[str, dict] = {
    "indiv": {
        "table": "individual_contributions",
        "columns": [
            "cmte_id", "amndt_ind", "rpt_tp", "transaction_pgi", "image_num",
            "transaction_tp", "entity_tp", "name", "city", "state", "zip_code",
            "employer", "occupation", "transaction_dt", "transaction_amt",
            "other_id", "tran_id", "file_num", "memo_cd", "memo_text", "sub_id",
        ],
    },
    "pas2": {
        "table": "pac_contributions",
        "columns": [
            "cmte_id", "amndt_ind", "rpt_tp", "transaction_pgi", "image_num",
            "transaction_tp", "entity_tp", "name", "city", "state", "zip_code",
            "employer", "occupation", "transaction_dt", "transaction_amt",
            "other_id", "cand_id", "tran_id", "file_num", "memo_cd", "memo_text", "sub_id",
        ],
    },
    "cn": {
        "table": "candidates",
        "columns": [
            "cand_id", "cand_name", "cand_pty_affiliation", "cand_election_yr",
            "cand_office_st", "cand_office", "cand_office_district", "cand_ici",
            "cand_status", "cand_pcc", "cand_st1", "cand_st2", "cand_city",
            "cand_st", "cand_zip",
        ],
    },
    "cm": {
        "table": "committees",
        "columns": [
            "cmte_id", "cmte_nm", "tres_nm", "cmte_st1", "cmte_st2", "cmte_city",
            "cmte_st", "cmte_zip", "cmte_dsgn", "cmte_tp", "cmte_pty_affiliation",
            "cmte_filing_freq", "org_tp", "connected_org_nm", "cand_id",
        ],
    },
    "ccl": {
        "table": "candidate_committee_linkage",
        "columns": [
            "cand_id", "cand_election_yr", "fec_election_yr",
            "cmte_id", "cmte_tp", "cmte_dsgn", "linkage_id",
        ],
    },
    # All-candidate financial summary derived from F3/F3P filings.
    # 30 columns per FEC bulk data format:
    # https://www.fec.gov/campaign-finance-data/all-candidates-file-description/
    "weball": {
        "table": "candidate_financial_summary",
        "columns": [
            "cand_id", "cand_name", "cand_ici", "pty_cd", "cand_pty_affiliation",
            "ttl_receipts", "trans_from_auth", "ttl_disb", "trans_to_auth",
            "coh_bop", "coh_cop", "cand_contrib", "cand_loans", "other_loans",
            "cand_loan_repay", "other_loan_repay", "debts_owed_by",
            "ttl_indiv_contrib", "cand_office_st", "cand_office_district",
            "spec_election", "prim_election", "run_election", "gen_election",
            "gen_election_precent", "other_pol_cmte_contrib", "pol_pty_contrib",
            "cvg_end_dt", "indiv_refunds", "cmte_refunds",
        ],
    },
}


def cycle_suffix(year: int) -> str:
    return str(year)[-2:]


def load_file(
    conn: duckdb.DuckDBPyConnection,
    file_type: str,
    data_file: Path,
    cycle_year: int,
) -> int:
    """
    Load a single FEC data file into DuckDB raw schema.
    Appends rows and tags them with cycle_year.
    Returns row count inserted.
    """
    spec = FILE_SPECS[file_type]
    table = f"raw.{spec['table']}"
    columns = spec["columns"]
    col_definitions = ", ".join(f"{c} VARCHAR" for c in columns)

    # Ensure table exists (idempotent)
    conn.execute(f"""
        CREATE TABLE IF NOT EXISTS {table} (
            {col_definitions},
            cycle_year INTEGER,
            source_file VARCHAR
        )
    """)

    # Remove existing rows for this cycle + file (re-runnable)
    conn.execute(f"""
        DELETE FROM {table}
        WHERE cycle_year = {cycle_year}
          AND source_file = '{data_file.name}'
    """)

    # Load using DuckDB's native CSV reader (extremely fast).
    # Use the `columns` struct parameter (name -> type) instead of `column_names`
    # so that DuckDB applies names reliably across all 1.x versions.
    col_select = ", ".join(columns)
    col_struct = ", ".join(f"'{c}': 'VARCHAR'" for c in columns)
    conn.execute(f"""
        INSERT INTO {table}
        SELECT
            {col_select},
            {cycle_year}     AS cycle_year,
            '{data_file.name}' AS source_file
        FROM read_csv(
            '{data_file.as_posix()}',
            delim='|',
            header=false,
            columns={{{col_struct}}},
            ignore_errors=true
        )
    """)

    row_count = conn.execute(f"""
        SELECT count(*) FROM {table}
        WHERE cycle_year = {cycle_year} AND source_file = '{data_file.name}'
    """).fetchone()[0]

    return row_count


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Load extracted FEC files into DuckDB raw schema."
    )
    parser.add_argument(
        "--cycles", nargs="+", type=int, default=ALL_CYCLES, metavar="YEAR",
        help="Cycle years to load. Default: all available.",
    )
    parser.add_argument(
        "--extracted-dir", type=Path, default=Path("data/extracted"),
        help="Root of extracted FEC files. Default: data/extracted",
    )
    parser.add_argument(
        "--db", type=Path, default=Path("data/fec.duckdb"),
        help="DuckDB database file path. Default: data/fec.duckdb",
    )
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    args.db.parent.mkdir(parents=True, exist_ok=True)
    conn = duckdb.connect(str(args.db))
    conn.execute("CREATE SCHEMA IF NOT EXISTS raw")

    # Always ensure opensecrets_committees exists so DBT runs even without
    # OpenSecrets data. scripts/download_opensecrets.py populates it when available.
    conn.execute("""
        CREATE TABLE IF NOT EXISTS raw.opensecrets_committees (
            cycle VARCHAR, fec_id VARCHAR, pac_short VARCHAR, affiliate VARCHAR,
            ultorg VARCHAR, recip_id VARCHAR, recip_code VARCHAR, fec_cand_id VARCHAR,
            party VARCHAR, prim_code VARCHAR, source VARCHAR, sensitive VARCHAR,
            "foreign" VARCHAR, active VARCHAR,
            cycle_year INTEGER, source_file VARCHAR
        )
    """)
    log.debug("Ensured raw.opensecrets_committees exists.")

    total_rows = 0

    for year in sorted(args.cycles):
        for file_type, spec in FILE_SPECS.items():
            # FEC extracts to a single .txt or .csv file inside the zip
            extract_dir = args.extracted_dir / str(year) / file_type
            if not extract_dir.exists():
                log.debug("Not extracted, skipping: %s / %s", year, file_type)
                continue

            # Glob for any .txt file directly in the extract dir (non-recursive).
            # This handles FEC renaming filenames across cycles (cn.txt, itcont.txt, etc.)
            matches = [f for f in extract_dir.glob("*.txt") if f.is_file()]
            if not matches:
                log.debug("No .txt file found in %s", extract_dir)
                continue
            data_file = matches[0]
            log.info("Loading %s (%d) from %s", spec['table'], year, data_file.name)

            rows = load_file(conn, file_type, data_file, year)
            log.info("  -> %d rows inserted into raw.%s", rows, spec['table'])
            total_rows += rows

    conn.close()
    log.info("=== Done. Total rows loaded: %d ===", total_rows)
    log.info("Database: %s", args.db.resolve())


if __name__ == "__main__":
    main()
