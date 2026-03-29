#!/usr/bin/env python3
"""
OpenSecrets PAC Committee Crosswalk Downloader
-----------------------------------------------
Downloads the OpenSecrets PAC files which map FEC committee IDs to
their real industry/category codes — the gold-standard classification
used by researchers and journalists.

OpenSecrets bulk data requires a free account:
  https://www.opensecrets.org/resources/create/

Set credentials via environment variables:
  OPENSECRETS_EMAIL=your@email.com
  OPENSECRETS_PASSWORD=yourpassword

Or pass a pre-downloaded zip file directly with --file.

Usage:
    # Download from OpenSecrets (requires account)
    python scripts/download_opensecrets.py --cycles 2024 2022

    # Load a manually downloaded file
    python scripts/download_opensecrets.py --file ~/Downloads/pacs24.zip --cycles 2024

    # Load into DuckDB after download
    python scripts/download_opensecrets.py --cycles 2024 --load
"""

import argparse
import logging
import os
import zipfile
from pathlib import Path

import requests
import duckdb

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

ALL_CYCLES = list(range(1990, 2025, 2))

LOGIN_URL  = "https://www.opensecrets.org/api/login"
BASE_URL   = "https://www.opensecrets.org/bulk-data/downloads"

# OpenSecrets PAC file columns (pacs{yy}.txt)
PAC_COLUMNS = [
    "cycle", "fec_id", "pac_short", "affiliate", "ultorg",
    "recip_id", "recip_code", "fec_cand_id", "party",
    "prim_code", "source", "sensitive", "foreign", "active",
]


def cycle_suffix(year: int) -> str:
    return str(year)[-2:]


def get_session(email: str, password: str) -> requests.Session:
    """Authenticate with OpenSecrets and return a logged-in session."""
    session = requests.Session()
    resp = session.post(LOGIN_URL, data={"email": email, "password": password}, timeout=30)
    resp.raise_for_status()
    if "logout" not in resp.text.lower():
        raise RuntimeError("OpenSecrets login failed — check credentials.")
    log.info("Authenticated with OpenSecrets.")
    return session


def download_pac_file(session: requests.Session, year: int, dest: Path) -> bool:
    """Download pacs{yy}.zip for a given cycle."""
    suffix = cycle_suffix(year)
    url = f"{BASE_URL}?f=pacs{suffix}.zip"

    if dest.exists():
        log.info("Already exists, skipping: %s", dest.name)
        return True

    dest.parent.mkdir(parents=True, exist_ok=True)
    log.info("Downloading OpenSecrets PAC file for %d ...", year)
    try:
        with session.get(url, stream=True, timeout=120) as resp:
            resp.raise_for_status()
            with open(dest, "wb") as fh:
                for chunk in resp.iter_content(chunk_size=1024 * 1024):
                    fh.write(chunk)
        return True
    except requests.RequestException as exc:
        log.error("Download failed: %s", exc)
        if dest.exists():
            dest.unlink()
        return False


def load_pac_file(zip_path: Path, year: int, db_path: Path) -> int:
    """
    Extract PAC zip and load into DuckDB raw.opensecrets_committees.
    Returns row count loaded.
    """
    extract_dir = zip_path.parent / f"extracted_{year}"
    extract_dir.mkdir(exist_ok=True)

    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(extract_dir)

    # Find the data file
    txt_files = list(extract_dir.glob("*.txt"))
    if not txt_files:
        log.error("No .txt found in %s", zip_path.name)
        return 0

    data_file = txt_files[0]
    log.info("Loading %s into raw.opensecrets_committees ...", data_file.name)

    conn = duckdb.connect(str(db_path))
    conn.execute("CREATE SCHEMA IF NOT EXISTS raw")

    # Quote reserved keywords in column definitions
    reserved = {"foreign", "source"}
    col_definitions = ", ".join(
        f'"{c}" VARCHAR' if c in reserved else f"{c} VARCHAR"
        for c in PAC_COLUMNS
    )
    conn.execute(f"""
        CREATE TABLE IF NOT EXISTS raw.opensecrets_committees (
            {col_definitions},
            cycle_year INTEGER,
            source_file VARCHAR
        )
    """)

    conn.execute(f"""
        DELETE FROM raw.opensecrets_committees
        WHERE cycle_year = {year}
    """)

    reserved = {"foreign", "source"}
    col_list = ", ".join(
        f'"{c}"' if c in reserved else c
        for c in PAC_COLUMNS
    )
    conn.execute(f"""
        INSERT INTO raw.opensecrets_committees
        SELECT {col_list}, {year}, '{data_file.name}'
        FROM read_csv(
            '{data_file.as_posix()}',
            delim=',',
            header=false,
            column_names={PAC_COLUMNS!r},
            all_varchar=true,
            ignore_errors=true
        )
    """)

    rows = conn.execute(
        f"SELECT count(*) FROM raw.opensecrets_committees WHERE cycle_year = {year}"
    ).fetchone()[0]
    conn.close()
    log.info("  -> %d rows loaded for cycle %d", rows, year)
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Download and load OpenSecrets PAC committee crosswalk."
    )
    parser.add_argument(
        "--cycles", nargs="+", type=int, default=[2024],
        metavar="YEAR", help="Election cycle years. Default: 2024",
    )
    parser.add_argument(
        "--file", type=Path, default=None,
        help="Path to a pre-downloaded OpenSecrets zip (skips download).",
    )
    parser.add_argument(
        "--data-dir", type=Path, default=Path("data/opensecrets"),
        help="Directory for OpenSecrets downloads. Default: data/opensecrets",
    )
    parser.add_argument(
        "--db", type=Path, default=Path("data/fec.duckdb"),
        help="DuckDB database path. Default: data/fec.duckdb",
    )
    parser.add_argument(
        "--load", action="store_true",
        help="Load downloaded files into DuckDB after downloading.",
    )
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # If a pre-downloaded file is provided, skip login and load directly
    if args.file:
        if not args.file.exists():
            raise SystemExit(f"File not found: {args.file}")
        for year in args.cycles:
            load_pac_file(args.file, year, args.db)
        return

    email    = os.environ.get("OPENSECRETS_EMAIL")
    password = os.environ.get("OPENSECRETS_PASSWORD")

    if not email or not password:
        raise SystemExit(
            "OpenSecrets credentials not set.\n"
            "  export OPENSECRETS_EMAIL=your@email.com\n"
            "  export OPENSECRETS_PASSWORD=yourpassword\n"
            "Or download manually from https://www.opensecrets.org/resources/create/\n"
            "and pass the file with: --file path/to/pacs24.zip"
        )

    session = get_session(email, password)

    for year in sorted(args.cycles):
        suffix = cycle_suffix(year)
        dest = args.data_dir / f"pacs{suffix}.zip"
        ok = download_pac_file(session, year, dest)
        if ok and args.load:
            load_pac_file(dest, year, args.db)

    log.info("Done.")


if __name__ == "__main__":
    main()
