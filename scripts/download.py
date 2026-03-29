#!/usr/bin/env python3
"""
FEC Bulk Data Downloader
------------------------
Downloads FEC election data files for all available cycles (1980-2024).

Usage:
    # Download everything
    python scripts/download.py

    # Download only 2024 and 2022 cycles
    python scripts/download.py --cycles 2024 2022

    # Download only specific file types for 2024, and extract them
    python scripts/download.py --cycles 2024 --file-types indiv pas2 cn cm --extract
"""

import argparse
import logging
import zipfile
from pathlib import Path

import requests
from tqdm import tqdm

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

# FEC election cycles: every even year from 1980 to 2024
ALL_CYCLES = list(range(1980, 2025, 2))

# FEC bulk file types and their descriptions
FILE_TYPES = {
    "indiv":   "Individual contributions (largest files, several GB per cycle)",
    "pas2":    "PAC-to-candidate contributions",
    "cn":      "Candidate master file",
    "cm":      "Committee master file",
    "ccl":     "Candidate-committee linkage",
    "weball":  "All-candidate financial summary (total receipts from F3/F3P filings — authoritative campaign totals)",
    "oppexp":  "Operating expenditures",
    "oth":     "Other committee transactions (party/inter-committee transfers)",
}

BASE_URL = "https://www.fec.gov/files/bulk-downloads"
CHUNK_SIZE = 1024 * 1024  # 1 MB per chunk


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def cycle_suffix(year: int) -> str:
    """Return the 2-digit suffix FEC uses in filenames for a given cycle year."""
    return str(year)[-2:]


def build_url(year: int, file_type: str) -> str:
    suffix = cycle_suffix(year)
    return f"{BASE_URL}/{year}/{file_type}{suffix}.zip"


def remote_content_length(url: str) -> int | None:
    """
    Return the Content-Length from a HEAD request, or None if unavailable/404.
    """
    try:
        resp = requests.head(url, timeout=30, allow_redirects=True)
        if resp.status_code == 404:
            return None
        resp.raise_for_status()
        length = resp.headers.get("content-length")
        return int(length) if length else 0  # 0 means "unknown size"
    except requests.RequestException as exc:
        log.debug("HEAD failed for %s: %s", url, exc)
        return None


def download_file(url: str, dest: Path) -> str:
    """
    Stream-download url to dest with a progress bar.

    Returns:
        "downloaded"  — file was fetched successfully
        "skipped"     — file already exists at the expected size
        "not_found"   — server returned 404
        "failed"      — network or I/O error
    """
    size = remote_content_length(url)

    if size is None:
        log.debug("Not found (404): %s", url)
        return "not_found"

    # Skip if already fully downloaded (size == 0 means unknown, re-download to be safe)
    if size > 0 and dest.exists() and dest.stat().st_size == size:
        log.info("Already complete, skipping: %s", dest.name)
        return "skipped"

    dest.parent.mkdir(parents=True, exist_ok=True)
    log.info("Downloading %-30s  ->  %s", dest.name, dest.parent)

    try:
        with requests.get(url, stream=True, timeout=120) as resp:
            resp.raise_for_status()
            total = int(resp.headers.get("content-length", 0))
            with open(dest, "wb") as fh, tqdm(
                total=total or None,
                unit="B",
                unit_scale=True,
                unit_divisor=1024,
                desc=dest.name,
                leave=False,
            ) as bar:
                for chunk in resp.iter_content(chunk_size=CHUNK_SIZE):
                    fh.write(chunk)
                    bar.update(len(chunk))
        return "downloaded"

    except requests.RequestException as exc:
        log.error("Download failed for %s: %s", url, exc)
        if dest.exists():
            dest.unlink()  # Remove partial file
        return "failed"


def extract_zip(zip_path: Path, extract_dir: Path) -> None:
    extract_dir.mkdir(parents=True, exist_ok=True)
    log.info("Extracting %s  ->  %s", zip_path.name, extract_dir)
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(extract_dir)


# ---------------------------------------------------------------------------
# Core logic
# ---------------------------------------------------------------------------

def download_cycle(
    year: int,
    raw_dir: Path,
    file_types: list[str],
    extract: bool,
) -> dict[str, int]:
    """Download all requested file types for a single cycle year."""
    results = {"downloaded": 0, "skipped": 0, "not_found": 0, "failed": 0}
    cycle_dir = raw_dir / str(year)

    for ft in file_types:
        url = build_url(year, ft)
        dest = cycle_dir / f"{ft}{cycle_suffix(year)}.zip"
        status = download_file(url, dest)
        results[status] += 1

        if extract and status in ("downloaded", "skipped") and dest.exists():
            extract_dir = raw_dir.parent / "extracted" / str(year) / ft
            extract_zip(dest, extract_dir)

    return results


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download FEC bulk election data for all or selected cycles.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="\n".join(
            f"  {k:10s}  {v}" for k, v in FILE_TYPES.items()
        ),
    )
    parser.add_argument(
        "--cycles",
        nargs="+",
        type=int,
        default=ALL_CYCLES,
        metavar="YEAR",
        help="Election cycle years (e.g. 2024 2022). Default: all cycles 1980-2024.",
    )
    parser.add_argument(
        "--file-types",
        nargs="+",
        default=list(FILE_TYPES.keys()),
        choices=list(FILE_TYPES.keys()),
        metavar="TYPE",
        help="File types to download. Default: all types.",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=Path("data/raw"),
        help="Root directory for raw zip downloads. Default: data/raw",
    )
    parser.add_argument(
        "--extract",
        action="store_true",
        help="Extract zip files after download into data/extracted/{year}/{type}/",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable debug logging.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    invalid = [y for y in args.cycles if y not in ALL_CYCLES]
    if invalid:
        raise SystemExit(
            f"Invalid cycle years: {invalid}. Must be even years between 1980 and 2024."
        )

    cycles = sorted(args.cycles)
    log.info("FEC bulk downloader starting")
    log.info("  Cycles     : %s", cycles)
    log.info("  File types : %s", args.file_types)
    log.info("  Output dir : %s", args.data_dir.resolve())
    log.info("  Extract    : %s", args.extract)

    totals: dict[str, int] = {"downloaded": 0, "skipped": 0, "not_found": 0, "failed": 0}

    for year in cycles:
        log.info("--- Cycle %d ---", year)
        results = download_cycle(year, args.data_dir, args.file_types, args.extract)
        for key, val in results.items():
            totals[key] += val
        log.info(
            "  Cycle %d: downloaded=%d  skipped=%d  not_found=%d  failed=%d",
            year, results["downloaded"], results["skipped"],
            results["not_found"], results["failed"],
        )

    log.info("=== Final Summary ===")
    log.info("  Downloaded : %d", totals["downloaded"])
    log.info("  Skipped    : %d (already present)", totals["skipped"])
    log.info("  Not found  : %d (cycle/type combo doesn't exist on FEC)", totals["not_found"])
    log.info("  Failed     : %d", totals["failed"])

    if totals["failed"]:
        raise SystemExit(f"{totals['failed']} file(s) failed to download. Check logs above.")


if __name__ == "__main__":
    main()
