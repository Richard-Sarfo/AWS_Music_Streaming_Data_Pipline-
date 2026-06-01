# AWS Music Streaming Data Pipeline

Event-driven AWS pipeline that ingests irregular batches of streaming events from S3, validates and transforms them with AWS Glue, and lands daily genre KPIs in DynamoDB for downstream consumption by BI tools and applications.

The infrastructure is 100% Terraform-managed; the runtime is fully serverless (S3, EventBridge, Step Functions, Glue, DynamoDB, SNS, CloudWatch). All tooling runs inside Docker containers — nothing is installed on the host.

---

## Architecture

```
                 ┌────────────────────────────────────────────────────────────┐
                 │                      AWS Account                            │
                 │                                                             │
   New stream    │   ┌──────────┐   ObjectCreated   ┌────────────┐            │
   batch (CSV)   │   │ S3 data  │ ───────────────▶ │ EventBridge│            │
   ───────────▶  │   │  bucket  │                   │   rule     │            │
                 │   │ raw/...  │                   └──────┬─────┘            │
                 │   └──────────┘                          ▼                  │
                 │                              ┌─────────────────────┐       │
                 │                              │   Step Functions    │       │
                 │                              │   state machine     │       │
                 │                              └──────────┬──────────┘       │
                 │            ┌─────────────────┬──────────┼──────────┬─────┐ │
                 │            ▼                 ▼          ▼          ▼     ▼ │
                 │       ┌──────────┐    ┌──────────┐ ┌──────────┐ ┌──────┐  │
                 │       │ Validate │    │Transform │ │   Load   │ │Archive│ │
                 │       │(PyShell) │    │ (Spark)  │ │(PyShell) │ │ (S3)  │ │
                 │       └────┬─────┘    └────┬─────┘ └────┬─────┘ └───────┘  │
                 │            │ fail          │            │                  │
                 │            ▼               ▼            ▼                  │
                 │      rejected/        processed/   DynamoDB tables         │
                 │            │           kpis/run=*       │                  │
                 │            └────────────┐               │                  │
                 │                         ▼               ▼                  │
                 │                    ┌────────┐    ┌──────────────┐         │
                 │                    │  SNS   │    │ Downstream   │         │
                 │                    │ alerts │    │ apps / BI    │         │
                 │                    └────┬───┘    └──────────────┘         │
                 └─────────────────────────┼────────────────────────────────────┘
                                           ▼
                                       Email
```

### Why each component

| Service | Role |
| --- | --- |
| **S3** (data bucket, zoned) | Source of truth — raw, processed, archived, and rejected data; versioned + SSE-encrypted |
| **EventBridge** | Decouples ingestion timing — fires on every new object under `raw/streams/` |
| **Step Functions** | Orchestration with retries, catch branches, archive, and failure routing |
| **AWS Glue (Python Shell)** | Cheap CSV schema/null validation and DynamoDB batch loading (0.0625 DPU) |
| **AWS Glue (PySpark)** | Joins streams with the songs dimension and computes daily KPIs at scale |
| **DynamoDB** | Sub-10ms reads for downstream apps; key schema designed for partitioned queries |
| **SNS** | Email alerts on any pipeline failure |
| **CloudWatch Logs** | Step Functions execution logs and Glue job stdout/stderr |

---

## KPIs computed (per the brief)

Per `(genre, date)` — stored in `p1-streaming-dev-genre-daily-kpis`:

- `listen_count` — total plays
- `unique_listeners` — distinct users
- `total_listen_seconds` — sum of song durations across all plays
- `avg_listen_seconds_per_user` — `total_listen_seconds / unique_listeners`
- `top3_songs` — list of `{track_id, track_name, plays}` for the three most played in the genre that day

Per `date` — stored in `p1-streaming-dev-top-genres-daily`:

- Top 5 genres ranked by `listen_count`

> **Note on "total listening time":** `streams.csv` carries only `(user_id, track_id, listen_time-timestamp)`, no per-play duration. Each play is therefore credited with the song's `duration_ms` from `songs.csv`. If you need true elapsed-play duration, the upstream producer must add it to the event payload.

---

## Data model

```
p1-streaming-dev-genre-daily-kpis           p1-streaming-dev-top-genres-daily
  pk = GENRE#<genre>                          pk = DATE#<yyyy-mm-dd>
  sk = DATE#<yyyy-mm-dd>                      sk = RANK#<1..5>
  listen_count                                genre
  unique_listeners                            listen_count
  total_listen_seconds
  avg_listen_seconds_per_user
  top3_songs (List of Maps)
```

Both tables: `PAY_PER_REQUEST` billing, point-in-time recovery on, server-side encryption on. All access patterns are single-partition Query or GetItem — no Scan required. See [docs/ddb_sample_queries.md](docs/ddb_sample_queries.md) for examples.

---

## Repository layout

```
.
├── README.md                       # This file
├── docker-compose.yml              # tf + aws CLI containers
├── .env                            # AWS credentials & TF vars (gitignored)
├── .gitignore
├── terraform/                      # IaC for the whole pipeline
│   ├── providers.tf                # AWS provider + remote S3 backend
│   ├── variables.tf
│   ├── locals.tf
│   ├── s3.tf                       # Data + logs buckets, lifecycle, zones
│   ├── dynamodb.tf                 # Two KPI tables
│   ├── iam.tf                      # Glue / SFN / EventBridge roles
│   ├── glue.tf                     # 3 Glue jobs + uploaded scripts
│   ├── step_functions.tf           # Pipeline state machine
│   ├── observability.tf            # SNS topic + log group
│   ├── eventbridge.tf              # S3 → Step Functions rule
│   └── outputs.tf
├── glue_jobs/                      # Glue job source code (auto-uploaded)
│   ├── validate_streams.py         # Python Shell — schema & null checks
│   ├── transform_kpis.py           # PySpark — KPI computation
│   └── load_dynamodb.py            # Python Shell — BatchWriteItem loader
├── docs/
│   └── ddb_sample_queries.md
└── data/                           # Sample datasets (uploaded to S3 at seed)
    ├── songs/songs.csv             # 89,741 tracks (genre, duration, features)
    ├── users/users.csv             # 50,000 profiles
    └── streams/streams[1-3].csv    # 3 batches of 11,346 listen events
```

---

## Prerequisites

- **Docker Desktop** running (the only host requirement)
- An AWS account with IAM permissions for: S3, DynamoDB, Glue, Step Functions, EventBridge, IAM, SNS, CloudWatch Logs
- An IAM access key pair (paste into `.env`)

---

## Configuration

Create `.env` at the repo root (it is `.gitignore`d):

```bash
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_DEFAULT_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012
TF_VAR_env=dev
TF_VAR_alert_email=you@example.com
```

The Terraform backend bucket is currently hard-coded to account `982081084448` in [terraform/providers.tf](terraform/providers.tf). Adjust the `bucket` and bootstrap commands below to your account ID.

---

## Deployment

### 1. Bootstrap — Terraform state bucket + lock table (run once per account)

```powershell
docker compose run --rm aws s3api create-bucket `
  --bucket p1-tfstate-dev-$env:AWS_ACCOUNT_ID --region us-east-1

docker compose run --rm aws s3api put-bucket-versioning `
  --bucket p1-tfstate-dev-$env:AWS_ACCOUNT_ID `
  --versioning-configuration Status=Enabled

docker compose run --rm aws dynamodb create-table `
  --table-name p1-tflock-dev `
  --attribute-definitions AttributeName=LockID,AttributeType=S `
  --key-schema AttributeName=LockID,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST --region us-east-1
```

### 2. Provision the pipeline

```powershell
docker compose run --rm tf init
docker compose run --rm tf fmt -recursive
docker compose run --rm tf validate
docker compose run --rm tf plan  -var "alert_email=$env:TF_VAR_alert_email"
docker compose run --rm tf apply -auto-approve -var "alert_email=$env:TF_VAR_alert_email"
```

Confirm the SNS subscription via the email AWS sends you. Without confirmation, failure alerts will be silently dropped.

### 3. Seed dimensions and trigger the first run

```powershell
$BUCKET = docker compose run --rm tf output -raw data_bucket

docker compose run --rm aws s3 cp /work/data/songs/songs.csv s3://$BUCKET/raw/songs/songs.csv
docker compose run --rm aws s3 cp /work/data/users/users.csv s3://$BUCKET/raw/users/users.csv

# Dropping this file under raw/streams/ triggers an end-to-end execution.
docker compose run --rm aws s3 cp /work/data/streams/streams1.csv s3://$BUCKET/raw/streams/streams1.csv
```

---

## Running the pipeline

The pipeline is **event-driven**: dropping any new file under `s3://<data_bucket>/raw/streams/` starts a fresh Step Functions execution. There is no schedule to maintain and no batching window — files are processed as they land.

```powershell
$SM = docker compose run --rm tf output -raw state_machine
docker compose run --rm aws stepfunctions list-executions --state-machine-arn $SM --max-results 5
docker compose run --rm aws dynamodb scan --table-name p1-streaming-dev-top-genres-daily --max-items 10
```

On success: the source file is moved to `archive/raw/streams/<name>.csv` (transitions to Glacier IR after 90 days, expires after 7 years per the GDPR-aligned lifecycle rule).

On validation failure: the file is moved to `rejected/raw/streams/<name>.csv` (auto-expires after 30 days) and an SNS alert fires.

---

## Observability

| Where | What you'll find |
| --- | --- |
| **CloudWatch Logs** — `/aws/vendedlogs/states/p1-streaming-dev-pipeline` | Step Functions execution history with `include_execution_data=true` |
| **CloudWatch Logs** — `/aws-glue/jobs/output` and `/aws-glue/jobs/error` | Glue job stdout/stderr, including the validator's JSON report |
| **SNS topic** — `p1-streaming-dev-alerts` | Email on any caught Step Functions failure |
| **S3 access logs** — `s3://p1-streaming-dev-logs-<acct>/s3-access/` | Object-level access audit on the data bucket |

---

## Cost profile (us-east-1, indicative)

- **Glue Python Shell** jobs run at 0.0625 DPU — roughly $0.0029/min
- **Glue PySpark** job runs at 2 × G.1X — roughly $0.88/hr while running
- **DynamoDB** is on-demand — pay only per write/read request
- **S3** lifecycle: archived files transition to Glacier IR after 90 days; rejected files expire after 30
- **Step Functions** Standard workflow — $0.025 per 1,000 state transitions

A typical run on the sample `streams1.csv` (11,346 events) completes in under 3 minutes end-to-end and costs cents.

---

## Security

- **No credentials in source.** `.env` is `.gitignore`d. Glue jobs use IAM role credentials supplied automatically by AWS — they do not read `.env`.
- **Least-privilege IAM.** Each role's inline policy is scoped to the specific bucket ARN, table ARNs, and SNS topic ARN it needs. See [terraform/iam.tf](terraform/iam.tf).
- **Encryption.** All S3 buckets use SSE-AES256 by default. DynamoDB tables enable AWS-managed SSE.
- **Public access fully blocked** on the data bucket (`aws_s3_bucket_public_access_block`).
- **Versioning + PITR** are on for the data bucket and both DynamoDB tables, giving point-in-time recovery against accidental writes/deletes.
- **Rotate the access key** you used during deployment — pasted access keys end up in shell history and chat transcripts.

---

## Teardown

```powershell
docker compose run --rm tf destroy -var "alert_email=$env:TF_VAR_alert_email"
```

S3 buckets must be empty before `destroy` succeeds. If you've run the pipeline at least once, run:

```powershell
docker compose run --rm aws s3 rm s3://$BUCKET --recursive
```

before `tf destroy`. The bootstrap bucket and lock table are intentionally not torn down — they survive across deployments.

---

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `tf init` fails with backend `NoSuchBucket` | Step 1 bootstrap not run, or the bucket name in `terraform/providers.tf` doesn't match your account ID |
| Step Functions stays in `RUNNING` for >15 min | Glue PySpark job throttled — check `glue:StartJobRun` quota; increase `max_concurrent_runs` in [terraform/glue.tf](terraform/glue.tf) |
| Validator rejects a file you expected to pass | Check `--null_rate` in the validator's exit message — threshold is 5% on `user_id`, `track_id`, `listen_time` (see [glue_jobs/validate_streams.py](glue_jobs/validate_streams.py)) |
| DynamoDB items missing after a successful run | Open the Step Functions execution and confirm `Load` task succeeded; check the loader's printed JSON for `genre_items_written` / `top_items_written` |
| No SNS email on failure | Confirm the subscription via the email you received after `tf apply` — pending subscriptions don't deliver |
