# FEC Money Trail Analyzer
# Usage: make <target> [CYCLES="2024 2022"] [FILE_TYPES="indiv pas2 cn cm ccl weball"] [DB=data/fec.duckdb]

.DEFAULT_GOAL := help

# ── Configurable variables ────────────────────────────────────────────────────
CYCLES     ?= 2024
FILE_TYPES ?= indiv pas2 cn cm ccl weball
DB         ?= data/fec.duckdb
DBT_DIR    := dbt

# dbt profiles.yml reads FEC_DB_PATH; pass absolute path so it works from dbt/
export FEC_DB_PATH := $(abspath $(DB))

.PHONY: help download extract load dbt-seed dbt-run dbt-test dbt-clean pipeline clean

# ── Help ──────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "FEC Money Trail Analyzer"
	@echo "========================"
	@echo ""
	@echo "Data pipeline:"
	@echo "  download        Download FEC zip files (no extraction)"
	@echo "  extract         Download and extract FEC zip files"
	@echo "  load            Load extracted files into DuckDB"
	@echo "  pipeline        Full run: extract -> load -> dbt-seed -> dbt-run -> dbt-test"
	@echo ""
	@echo "dbt:"
	@echo "  dbt-seed        Load CSV reference seeds into DuckDB"
	@echo "  dbt-run         Build all dbt models"
	@echo "  dbt-test        Run all dbt tests"
	@echo "  dbt-clean       Remove dbt target/ and dbt_packages/"
	@echo ""
	@echo "Housekeeping:"
	@echo "  clean           Remove data/raw, data/extracted, and dbt build artifacts"
	@echo ""
	@echo "Variables (override on the command line):"
	@echo "  CYCLES       Space-separated election cycle years  (default: $(CYCLES))"
	@echo "  FILE_TYPES   FEC file types to download            (default: $(FILE_TYPES))"
	@echo "  DB           DuckDB database path                  (default: $(DB))"
	@echo ""
	@echo "Examples:"
	@echo "  make pipeline"
	@echo "  make pipeline CYCLES=\"2024 2022 2020\""
	@echo "  make extract  CYCLES=2024 FILE_TYPES=\"indiv cn cm ccl weball\""
	@echo "  make load     CYCLES=2024"
	@echo ""

# ── Data ingestion ────────────────────────────────────────────────────────────
download:
	python scripts/download.py --cycles $(CYCLES) --file-types $(FILE_TYPES)

extract:
	python scripts/download.py --cycles $(CYCLES) --file-types $(FILE_TYPES) --extract

load:
	python scripts/load.py --cycles $(CYCLES) --db $(DB)

# ── dbt ───────────────────────────────────────────────────────────────────────
dbt-seed:
	cd $(DBT_DIR) && dbt seed

dbt-run:
	cd $(DBT_DIR) && dbt run

dbt-test:
	cd $(DBT_DIR) && dbt test

dbt-clean:
	cd $(DBT_DIR) && dbt clean

# ── Composite ─────────────────────────────────────────────────────────────────
pipeline: extract load dbt-seed dbt-run dbt-test

# ── Housekeeping ──────────────────────────────────────────────────────────────
clean: dbt-clean
	rm -rf data/raw data/extracted
