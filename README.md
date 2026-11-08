# Clinical Data Pipeline

Synthetic EHR data (Synthea) → Postgres → SQL analytics answering real
clinical/operational questions: readmissions, care gaps, utilization, cost,
and data quality.

> All data is synthetic. No real patient information (PHI) is used.

## Architecture

```
Synthea (Java)  →  CSV files  →  raw schema      →  clinical schema    →  analysis queries
  generates         on disk      (all TEXT,          (typed, cleaned,      (business
  fake patients                  as received)        indexed)              questions)
                    load_raw.py                01_staging.sql         queries/analysis.sql
```

Why three layers? `raw` keeps an untouched copy of the source so a bad
value never breaks the load and you can always debug against the original.
`clinical` is where typing and cleanup happen. Analysis only ever reads
`clinical`.

## Prerequisites

- Docker Desktop
- Java 11+ (to run Synthea)
- Python 3.10+

## Setup

### 1. Start Postgres
```bash
cp .env.example .env
docker compose up -d
```

### 2. Generate synthetic patients
Download `synthea-with-dependencies.jar` from the Synthea GitHub releases
page and put it in `synthea/`. Then:
```bash
cd synthea
java -jar synthea-with-dependencies.jar -s 42 -p 1000 \
  --exporter.csv.export true --exporter.fhir.export false \
  Pennsylvania Philadelphia
cd ..
```
- `-s 42` is a random seed, so anyone can regenerate the exact same data.
- `-p 1000` = 1,000 living patients (Synthea adds deceased ones on top).
- FHIR export is off for now; it comes back in Phase 2.

CSVs land in `synthea/output/csv/`.

### 3. Load raw data
```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python scripts/load_raw.py
```

### 4. Build the clean tables
```bash
docker exec -i clinical-db psql -U clinical -d clinical -f /sql/01_staging.sql
```

### 5. Run the analysis
Open `queries/analysis.sql` in DBeaver (localhost:5432, user/pass/db
`clinical`) or in psql:
```bash
docker exec -it clinical-db psql -U clinical -d clinical
```

## Findings

<!-- Fill in as you finish each query: the number + one sentence of "so what". -->

| # | Question | Answer | So what |
|---|----------|--------|---------|
| 1 | Patients by gender, living vs deceased | | |
| 2 | Top 10 active conditions | | |
| 3 | Encounters per patient by class | | |
| 4 | 30-day inpatient readmission rate | | |
| 5 | Top condition per age group | | |
| 6 | Diabetics missing an HbA1c in 12 months | | |
| 7 | Cost by encounter class | | |
| 8 | Data quality check results | | |

## Roadmap

- [ ] **Phase 1** — Synthea → Postgres → 8 analysis queries (current)
- [ ] **Phase 2** — Automated data quality tests in CI (GitHub Actions)
- [ ] **Phase 3** — FHIR API with Spring Boot
- [ ] **Phase 4** — Dashboard (Power BI or Tableau)
- [ ] **Phase 5** — Deploy to AWS (RDS + S3)
