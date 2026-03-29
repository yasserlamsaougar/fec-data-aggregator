# FEC Money Trail Analyzer

A data engineering pipeline that traces the flow of political money in US federal elections using public bulk data from the [Federal Election Commission (FEC)](https://www.fec.gov/data/browse-data/?tab=bulk-data).

The goal: given any federal candidate, answer **who funds them, how much, from which industries, and how captured they are by special interests** — producing a transparent, reproducible corruption-risk score.

---

## Why This Matters

Campaign finance is public record, but it is buried in millions of rows of raw government data. This project automates the full pipeline from raw FEC files to actionable insights:

- A pharmaceutical company donating heavily to a candidate on the House Energy & Commerce Committee is a signal, not a coincidence
- A Super PAC with a vague name ("Citizens for a Better Tomorrow") masking its industry origin is a dark money flag
- A candidate receiving 80% of their funds from PACs and 5% from small individual donors has a very different accountability profile than one funded mainly by grassroots donations

---

## Stack

| Layer | Technology | Purpose |
|---|---|---|
| Ingestion | Python + `requests` | Bulk download FEC zip files |
| Storage | DuckDB | Embedded analytical database, no server required |
| Transformation | DBT (dbt-duckdb) | Multi-layer SQL modeling, tests, lineage |
| Orchestration | GitHub Actions | Scheduled pipeline, CI validation |
| Reference data | CSV seed (DBT) | Industry taxonomy (keyword → industry mapping) |

---

## Architecture

```
FEC Website (bulk zips)
        │
        ▼
scripts/download.py         Download + extract zip files
        │
        ▼
data/extracted/{year}/{type}/   Raw pipe-delimited .txt files
        │
        ▼
scripts/load.py             Load into DuckDB raw schema
        │
        ▼
DuckDB: raw.*               Raw tables (all VARCHAR, untouched)
        │
        ▼
DBT staging/                Clean, type-cast, decode FEC codes
        │
        ▼
DBT intermediate/           Enrich, join, tag industries, flag dark money
        │
        ▼
DBT marts/                  Aggregated funding summaries + corruption scores
```

---

## FEC Data Sources

All data is downloaded from the official FEC bulk data portal:
`https://www.fec.gov/data/browse-data/?tab=bulk-data`

Files are organized by **election cycle** (two-year periods ending in an even year: 1980, 1982, … 2024).

### File Types

FEC zip files are named `{type}{yy}.zip` (e.g. `indiv24.zip`), but the `.txt` file extracted inside can vary by cycle. The loader automatically discovers whichever `.txt` file is present — no hardcoded filenames.

| Download key | Table | Description | Approx. size (2024 cycle) |
|---|---|---|---|
| `indiv` | `individual_contributions` | Every itemized donation from an individual to a committee | ~4 GB |
| `pas2` | `pac_contributions` | PAC, party, and committee contributions directly to candidates | ~200 MB |
| `cn` | `candidates` | All registered federal candidates | ~5 MB |
| `cm` | `committees` | All registered political committees (PACs, campaigns, parties) | ~10 MB |
| `ccl` | `candidate_committee_linkage` | Maps candidates to their authorized committees | ~3 MB |
| `weball` | `candidate_financial_summary` | **All-candidate financial summary from F3/F3P filings.** Self-reported total receipts including unitemized small donations (<$200) — the authoritative campaign total. | ~5 MB |
| `oppexp` | _(future)_ | Operating expenditures by committees | ~500 MB |
| `oth` | _(future)_ | Other inter-committee transactions | ~100 MB |

Files use `|` (pipe) as delimiter with **no header row** — column names are applied by `scripts/load.py`.

---

## Column Reference

### `individual_contributions` (from `indiv` zip)

| Column | Description |
|---|---|
| `cmte_id` | Receiving committee ID (links to `committees`) |
| `entity_tp` | Donor entity type: `IND`=Individual, `ORG`=Organization, `PAC`, `PTY`=Party |
| `name` | Donor full name |
| `city` / `state` / `zip_code` | Donor location |
| `employer` | Donor's employer (key for industry tagging) |
| `occupation` | Donor's occupation |
| `transaction_dt` | Date in `MMDDYYYY` format |
| `transaction_amt` | Amount in USD (negative = refund) |
| `transaction_tp` | Type code: `15`=contribution, `22Y`=refund, `15E`=earmarked |
| `transaction_pgi` | Election stage: `P`=Primary, `G`=General, `R`=Runoff |
| `other_id` | If earmarked, the ultimate recipient committee ID |
| `tran_id` | FEC internal transaction ID |
| `sub_id` | Unique submission ID (used as primary key) |
| `memo_text` | Optional memo (e.g. "EARMARKED FOR ...") |

### `pac_contributions` (from `pas2` zip)

Same structure as individual contributions plus:

| Column | Description |
|---|---|
| `cand_id` | Candidate receiving the contribution (direct link) |

### `candidates` (from `cn` zip)

| Column | Description |
|---|---|
| `cand_id` | Unique FEC candidate ID (e.g. `P00009423`) |
| `cand_name` | Candidate full name |
| `cand_pty_affiliation` | Party: `DEM`, `REP`, `IND`, `LIB`, `GRE`, etc. |
| `cand_election_yr` | Election year |
| `cand_office` | Office sought: `P`=President, `S`=Senate, `H`=House |
| `cand_office_st` | State (for Senate/House) |
| `cand_office_district` | District number (for House) |
| `cand_ici` | Incumbent/Challenger/Open: `I`, `C`, `O` |
| `cand_status` | FEC registration status |
| `cand_pcc` | Principal Campaign Committee ID |

### `committees` (from `cm` zip)

| Column | Description |
|---|---|
| `cmte_id` | Unique FEC committee ID (e.g. `C00575795`) |
| `cmte_nm` | Committee name |
| `cmte_dsgn` | Designation: `P`=Principal Campaign, `A`=Authorized, `D`=Leadership PAC, `U`=Unauthorized |
| `cmte_tp` | Type: `H`/`S`/`P`=Candidate committees, `N`/`Q`=PAC, `O`=Super PAC, `X`/`Y`=Party |
| `org_tp` | Organization type: `C`=Corporation, `L`=Labor, `T`=Trade Assoc., `M`=Membership |
| `connected_org_nm` | Sponsoring organization name (critical for industry tagging) |
| `cand_id` | Linked candidate (if a campaign committee) |

### `candidate_committee_linkage` (from `ccl` zip)

| Column | Description |
|---|---|
| `cand_id` | Candidate ID |
| `cmte_id` | Authorized committee ID |
| `cmte_dsgn` | Committee designation |
| `fec_election_yr` | FEC election year for this linkage |
| `linkage_id` | Unique linkage record ID |

---

## DBT Model Layers

### Staging (`models/staging/`) — Views

Clean and standardize the raw data. Each model maps 1:1 to a raw FEC file.

| Model | What it does |
|---|---|
| `stg_candidates` | Decodes party codes, office codes, incumbent status |
| `stg_committees` | Decodes committee types, designations, org types; flags Super PACs |
| `stg_individual_contributions` | Parses dates, casts amounts, classifies donation size buckets, flags refunds |
| `stg_pac_contributions` | Same as above for PAC-to-candidate transactions |
| `stg_candidate_committee_linkage` | Clean linkage between candidates and their committees |
| `stg_candidate_financial_summary` | F3/F3P self-reported totals: total receipts, itemized/unitemized individual contributions, PAC contributions, loans, disbursements, coverage dates |

### Intermediate (`models/intermediate/`) — Tables

Join and enrich staging data.

| Model | What it does |
|---|---|
| `int_contributions_to_candidates` | Unified view of all money flowing to each candidate (both PAC-direct and individual-via-committee paths) |
| `int_committee_industry_tags` | Tags every committee with an industry using keyword matching against the `industry_taxonomy` seed; flags dark money suspects |

### Marts (`models/marts/`) — Tables

Final analytical outputs. One row per candidate per election cycle.

| Model | What it does |
|---|---|
| `mart_candidate_funding_summary` | Per-candidate funding totals broken down by PAC vs individual, industry sector, Super PAC, dark money, and % ratios |
| `mart_candidate_corruption_score` | 0–100 donor-capture score with penalty/bonus components, percentile rankings, and risk tier |

#### `mart_candidate_funding_summary` columns

**Identity**

| Column | Type | Description |
|---|---|---|
| `candidate_id` | varchar | FEC candidate ID (e.g. `H2NY10092`) |
| `candidate_name` | varchar | Display name normalized to Title Case (`"Bernard Sanders"`). Falls back to raw ID if cn file for the candidate's cycle was not loaded. |
| `party_name` | varchar | `Democrat`, `Republican`, `Independent`, `Libertarian`, `Green`, `Other / Unknown` |
| `office` | varchar | `House`, `Senate`, `President` |
| `office_state` | varchar | Two-letter state abbreviation |
| `election_year` | integer | Election cycle year (2-year even cycles) |
| `incumbent_challenger_status` | varchar | `Incumbent`, `Challenger`, `Open Seat`, `Unknown` |
| `has_candidate_profile` | boolean | `true` if a matching cn record was found. `false` means contribution data exists but the candidate file for that cycle was not loaded — name will show the raw ID. |

**Volume**

| Column | Type | Description |
|---|---|---|
| `total_transactions` | integer | Total contribution rows (PAC + individual) |
| `total_raised` | decimal | Sum of captured itemized transactions (PAC + individual). Always populated. Lower than `total_receipts_reported` — excludes unitemized small donations (<$200), leadership PAC receipts, and JFC pass-throughs. |
| `total_receipts_reported` | decimal | **Authoritative campaign total from F3/F3P self-reporting.** Includes unitemized small donations. Null if `weball` not loaded for this cycle. Use as the headline fundraising figure. |
| `ind_total_reported` | decimal | Total individual contributions per campaign report (itemized + unitemized, self-reported). The weball file does not break out the unitemized portion separately. |
| `pct_coverage` | decimal | `total_raised / total_receipts_reported × 100`. Low coverage = large small-donor base or significant leadership PAC activity. |
| `financial_report_thru` | date | End date of the most recent F3/F3P report period. |

**Raised by path**

| Column | Type | Description |
|---|---|---|
| `raised_from_pacs` | decimal | Dollars from direct PAC-to-candidate contributions (pas2 file) |
| `raised_from_individuals` | decimal | Dollars from individual donors via authorized committees |

**Raised by industry group** — unified across PAC and individual sources

| Column | Type | Description |
|---|---|---|
| `raised_from_pharma` | decimal | Pharma & Healthcare industry group |
| `raised_from_finance` | decimal | Finance & Banking |
| `raised_from_defense` | decimal | Defense & Military |
| `raised_from_energy` | decimal | Energy & Oil |
| `raised_from_tech` | decimal | Tech & Telecom |
| `raised_from_aipac_aligned` | decimal | Israel / AIPAC-aligned committees and donors |
| `raised_from_dark_money` | decimal | Super PAC committees with no identified industry (dark money suspects) |
| `raised_from_super_pacs` | decimal | Direct contributions from Super PAC (type O) committees. Note: Super PACs are legally prohibited from making direct contributions to candidates; a non-zero value here indicates a committee classified as type O in the FEC cm file. |

**Classification coverage** — how confident is the industry tagging

| Column | Type | Description |
|---|---|---|
| `classified_by_opensecrets` | decimal | Dollars tagged via OpenSecrets catcode crosswalk (highest confidence) |
| `classified_by_employer` | decimal | Dollars tagged via donor employer keyword match |
| `classified_by_keyword` | decimal | Dollars tagged via committee name keyword match (fallback) |
| `unclassified_amount` | decimal | Dollars with no industry match across all three layers |
| `pct_classified` | decimal | `(total_raised − unclassified_amount) / total_raised × 100` |

**Grassroots signals**

| Column | Type | Description |
|---|---|---|
| `unique_donor_count` | integer | Distinct individual donor names |
| `median_individual_donation` | decimal | Median donation amount among individual contributions. More robust than average for detecting genuine small-donor campaigns. |
| `pct_individual_from_large` | decimal | % of individual-path dollars from donations ≥ $1,000. High value = large bundlers dominate despite many small donors. |

**Percentage ratios** (derived, added in the final SELECT)

| Column | Type | Description |
|---|---|---|
| `pct_from_pacs` | decimal | `raised_from_pacs / total_raised × 100` |
| `pct_from_individuals` | decimal | `raised_from_individuals / total_raised × 100` |
| `pct_dark_money` | decimal | `raised_from_dark_money / total_raised × 100` |
| `pct_super_pac` | decimal | `raised_from_super_pacs / total_raised × 100` |

---

#### `mart_candidate_corruption_score` columns

Inherits all columns from `mart_candidate_funding_summary`, plus:

**Derived inputs used in scoring**

| Column | Type | Description |
|---|---|---|
| `pct_large_donors` | decimal | % of `total_raised` that came from individual donations ≥ $1,000 (differs from `pct_individual_from_large` which is % *within* individual money) |
| `pct_top_industry` | decimal | The single largest industry group as % of `total_raised` |

**Penalty components** (higher = more institutional capture)

| Column | Type | Description |
|---|---|---|
| `penalty_pac_concentration` | decimal | `pct_from_pacs × 0.70`, capped at 70 |
| `penalty_dark_money` | decimal | `pct_dark_money × 0.50`, capped at 40 |
| `penalty_super_pac` | decimal | `pct_super_pac × 0.30`, capped at 20 |
| `penalty_large_donors` | decimal | `pct_large_donors × 0.30`, capped at 30 |
| `penalty_industry_capture` | decimal | `pct_top_industry × 0.20`, capped at 20 |

**Grassroots bonus components** (higher = more grassroots, subtracts from score)

| Column | Type | Description |
|---|---|---|
| `bonus_individual_pct` | decimal | `pct_from_individuals × 0.15 × (1 − pct_individual_from_large / 100)`, capped at 15. Conditioned on small-donor share — bundled large-donor candidates earn a reduced bonus. |
| `bonus_donor_distribution` | decimal | Up to 10 pts: 5 pts for low median donation + 5 pts for low large-donor share of individual revenue |

**Final score and rankings**

| Column | Type | Description |
|---|---|---|
| `corruption_score` | decimal | Sum of penalties minus bonuses, clamped to 0–100 |
| `score_pct_within_office` | decimal | Percentile vs. candidates in the same office + election year (0 = cleanest) |
| `score_decile_within_office` | integer | Decile 1–10 within same office + year (1 = cleanest 10%, 10 = most captured) |
| `score_pct_overall` | decimal | Percentile across all candidates and offices |
| `risk_tier` | varchar | `Lower Risk` (0–14), `Moderate Risk` (15–44), `High Risk` (45+) |

---

## Corruption Score Methodology

The score is a net composite of penalty and grassroots bonus components, clamped to 0–100.

### Penalty components (max 160 pts before clamping to 100)

| Component | Weight | Cap | Signal |
|---|---|---|---|
| PAC concentration | ×0.70 | 70 | % of total funding from PACs |
| Dark money | ×0.50 | 40 | % from Super PACs with no identified industry |
| Large donor share | ×0.30 | 30 | % of total raised from donations ≥ $1,000 |
| Super PAC reliance | ×0.30 | 20 | % from Super PAC committees (type O) |
| Industry capture | ×0.20 | 20 | Single industry dominates funding |

### Grassroots bonus (max −25 pts, reduces score)

| Component | Max pts off | Signal |
|---|---|---|
| Individual donor % | −15 | Scaled by small-donor share — high individual % only earns the full bonus when large bundlers don't dominate |
| Donor distribution | −10 | Low **median** donation AND low large-donor share of individual revenue |

Average donation is deliberately **not used** — it can be gamed by flooding a campaign with micro-donations while large bundled donors remain in the mix. A candidate can post a $16 median while 49% of their individual money comes from $2,800 donors. Instead:

- **Median individual donation** — robust to volume tricks
- **`pct_individual_from_large`** — % of individual revenue from donors giving ≥ $1,000; exposes the "many small + few huge" pattern directly
- **Individual bonus is conditioned** — `pct_from_individuals × 0.15 × (1 − pct_individual_from_large/100)` so bundled-large-donor candidates like Jeffries earn roughly half the individual bonus compared to a true grassroots candidate

### Percentile rankings

Every candidate gets three percentile fields so the raw score has context:

| Field | Description |
|---|---|
| `score_pct_within_office` | Percentile vs. same office type + election year (primary comparison) |
| `score_decile_within_office` | Decile 1–10 (1 = cleanest 10%, 10 = most captured 10%) |
| `score_pct_overall` | Percentile across all candidates and all offices |

**Score interpretation:**

| Score | Risk tier | Meaning |
|---|---|---|
| 0–14 | Lower Risk | Funded primarily by small individual donors |
| 15–44 | Moderate Risk | Significant PAC/corporate or large-bundler presence |
| 45–100 | High Risk | Dominated by PACs, dark money, or bundled large donors |

> **Important:** The score is a signal, not a verdict. It reflects who funds a candidate, not how they vote. Use alongside policy records and voting history for full context.

---

## Industry Classification

Industry tags are assigned through a three-layer pipeline with explicit confidence tiers. Every contribution row carries a `match_source` field so reports can be transparent about classification quality.

| Layer | Source | `match_source` value | Confidence |
|---|---|---|---|
| 1 | OpenSecrets PAC crosswalk | `opensecrets` | Highest — researcher-verified |
| 2 | Donor employer field (individuals) | `employer_keyword` | High — direct company name |
| 3 | Committee / org name keywords | `committee_keyword` | Medium — name inference |
| — | No match | `unclassified` | Unknown |

### OpenSecrets Crosswalk

`scripts/download_opensecrets.py` downloads OpenSecrets' PAC committee files which map FEC committee IDs to their real industry category codes — the gold standard used by investigative journalists and researchers. Requires a free OpenSecrets account:

```bash
export OPENSECRETS_EMAIL=your@email.com
export OPENSECRETS_PASSWORD=yourpassword
python scripts/download_opensecrets.py --cycles 2024 --load
```

If OpenSecrets data is not available, the pipeline falls back to layers 2 and 3 automatically. An empty `raw.opensecrets_committees` table is always created so `dbt run` never fails without it.

### Industry Taxonomy

The `dbt/seeds/industry_taxonomy.csv` seed maps keywords to industries (layers 2 and 3). The `dbt/seeds/opensecrets_categories.csv` seed maps OpenSecrets category codes to the same industry groups (layer 1).

All name fields are normalized in the staging layer before matching or display. Raw fields are preserved as `*_raw` columns for auditing.

### Name normalization rules

| Field | Normalization |
|---|---|
| Candidate name | Parsed from `LAST, FIRST` → `First Last` (Title Case) |
| Donor name | ALL CAPS → Title Case |
| Donor employer | Title Case, `&` → `And`, corporate suffixes stripped (`Inc`, `LLC`, `Corp`, etc.) |
| Committee name | ALL CAPS → Title Case |
| Connected org name | Same as employer |
| Cities | ALL CAPS → Title Case |

Employer normalization also improves taxonomy matching consistency — e.g. `JOHNSON & JOHNSON` and `JOHNSON AND JOHNSON` both normalize to `Johnson And Johnson`, matched by keyword `johnson and johnson`.

A reusable `normalize_name()` and `normalize_employer()` macro in `dbt/macros/normalize_name.sql` handles these transformations consistently across all staging models.

All FEC ID columns (`cmte_id`, `cand_id`) are `trim()`-ed at the staging layer. FEC pipe-delimited files sometimes contain trailing whitespace, which would silently break joins between staging models if left uncleaned.

Keywords are matched against the normalized committee name, connected organization name (PAC contributions), and donor employer field (individual contributions):

| Industry Group | Examples |
|---|---|
| Pharma & Healthcare | Pfizer, pharma, biotech, health insurance |
| Finance & Banking | Goldman Sachs, hedge fund, private equity, securities |
| Defense & Military | Lockheed, Raytheon, Northrop, Boeing Defense |
| Energy & Oil | ExxonMobil, Chevron, Koch, coal, pipeline |
| Tech & Telecom | Google, Meta, Amazon, Comcast, AT&T |
| Israel / AIPAC-aligned | AIPAC, American Israel, pro-Israel |
| Guns & Weapons | NRA, National Rifle Association, firearms |
| Labor | AFL-CIO, SEIU, Teamsters, teachers union |
| Agriculture | Farm Bureau, agribusiness |
| Party Committees | DNC, RNC, DCCC, DSCC, NRCC, NRSC |

Contributions from unmatched Super PACs are flagged as **dark money suspects**.

---

## Running the Pipeline

### Prerequisites
```
Python 3.12+
dbt-core + dbt-duckdb
duckdb
requests, tqdm
make
```

### Quick start — full pipeline

```bash
# 2024 cycle, all core file types, single command
make pipeline

# Multiple cycles
make pipeline CYCLES="2024 2022 2020"

# Custom file types
make pipeline CYCLES=2024 FILE_TYPES="indiv cn cm ccl weball"
```

Run `make` with no arguments to see all available targets and variables.

### Step-by-step

**Step 1 — Download and extract FEC data**

```bash
make extract CYCLES=2024

# IMPORTANT: also pull cn and weball for older cycles.
# PAC contributions reference candidates from any cycle — Bernie Sanders
# ran in 2016/2020, not 2024. Without their cn file, names show as IDs.
# Without weball, total_receipts_reported will be null for those cycles.
make extract CYCLES="2022 2020 2018 2016" FILE_TYPES="cn weball"

# All historical cycles, all files (~100 GB+)
make extract CYCLES="$(seq -s' ' 1980 2 2024)"
```

**Step 2 — Load into DuckDB**

```bash
make load CYCLES=2024
```

Re-running is safe — existing rows for the cycle are deleted before re-inserting.

**Step 3 — Run dbt**

```bash
make dbt-seed    # Load industry taxonomy CSV seeds
make dbt-run     # Build all models
make dbt-test    # Run data quality tests
```

Or directly:

```bash
cd dbt
dbt seed && dbt run && dbt test
```

### Outputs

After `dbt run`, query results directly in DuckDB:

```sql
-- Top 20 most PAC-funded Senate candidates in 2024
SELECT candidate_name, party_name, office_state,
       total_raised, pct_from_pacs, corruption_score, risk_tier
FROM marts.mart_candidate_corruption_score
WHERE office = 'Senate'
ORDER BY corruption_score DESC
LIMIT 20;
```

---

## Evidence.dev Dashboard

The `evidence/` directory contains an [Evidence.dev](https://evidence.dev) report site — SQL + markdown that compiles to a static website, deployable to GitHub Pages or Vercel for free.

### Pages

| Page | Route | What it shows |
|---|---|---|
| Overview | `/` | Key stats, top captured candidates, money by party, risk tier breakdown |
| Leaderboard | `/leaderboard` | Filterable corruption score rankings by office, party, year |
| Industries | `/industries` | Which sectors spend most, top recipients per industry, party breakdown |
| Dark Money | `/dark_money` | Suspected dark money PACs, top recipients, total funneled |
| Candidate Profile | `/candidate/[name]` | Full funding breakdown, score components, industry chart for any candidate |

### Running locally

```bash
cd evidence
npm install
npm run dev      # http://localhost:3000
```

### Building for production

```bash
cd evidence
npm run build    # outputs to evidence/build/
```

Deploy the `build/` folder to GitHub Pages, Vercel, or Netlify.

---

## GitHub Actions

| Workflow | Trigger | What it does |
|---|---|---|
| `pipeline.yml` | Monthly (1st) or manual | Full download → load → DBT run → export CSVs |
| `dbt_ci.yml` | Every push/PR to `dbt/` | Validates SQL with `dbt parse` + `dbt compile` (no data needed) |

Manual pipeline runs accept inputs: `cycles`, `file_types`, `skip_download`.

---

## Project Structure

```
fec-data-aggregator/
├── scripts/
│   ├── download.py          # FEC bulk downloader (all cycles, idempotent)
│   └── load.py              # Loads extracted files into DuckDB raw schema
├── dbt/
│   ├── dbt_project.yml
│   ├── profiles.yml         # DuckDB connection config
│   ├── seeds/
│   │   └── industry_taxonomy.csv
│   └── models/
│       ├── staging/         # 1:1 with raw FEC files, views
│       ├── intermediate/    # Joins, enrichment, industry tagging
│       └── marts/           # Final analytical tables + scoring
├── .github/workflows/
│   ├── pipeline.yml         # Full pipeline automation
│   └── dbt_ci.yml           # SQL validation on every PR
├── data/
│   ├── raw/                 # Downloaded zip files (gitignored)
│   └── extracted/           # Unzipped FEC text files (gitignored)
├── requirements.txt
└── README.md
```

---

## Data Limitations & Caveats

- **Itemization threshold:** Individual donations under $200 are not itemized by law and are absent from the `indiv` transaction file. The `weball` financial summary file surfaces this aggregate as `ind_unitemized_reported` — you can see the total but not the individual transactions. `pct_coverage` shows how much of the official total is captured in itemized data.
- **Self-funding:** Candidate personal loans to their own campaign appear in the data but are not captured by this scoring model as "outside influence."
- **Intermediary PACs:** Money laundered through multiple layers of PACs (a PAC funding a PAC funding a Super PAC) is difficult to fully trace — the dark money flag catches some but not all cases.
- **Industry taxonomy:** Keyword matching is approximate. A committee named "Americans for Progress" may be industry-aligned without revealing it in its name. The taxonomy will improve over time.
- **Score is additive, not normalized:** Candidates with very small fundraising totals can score high if most of it comes from one PAC. Filter by `total_raised` for meaningful comparisons.

---

## License

Data is sourced from the US Federal Election Commission, which publishes it as public domain.
Code in this repository is MIT licensed.
