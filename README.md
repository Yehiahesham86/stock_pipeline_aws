# Tutoring Platform CDC Pipeline — AWS infrastructure

Change data capture (CDC) from an online tutoring platform's Postgres database
into an Iceberg lakehouse on AWS, with row-level data quality checks and a
quarantine for bad rows. Everything is created and destroyed by Terraform from
this folder.

> **Status (2026-11-22):** Source → Raw → Bronze → Silver + quarantine run end
> to end on AWS. The first full run succeeded and quarantined exactly the 6 bad
> test rows. **Next:** Silver → Gold (dbt-athena), then stream Gold to an
> external tool.

---

## 1. Business questions (Gold layer, next phase)

1. **Teacher utilization**: completed vs. booked classes per teacher per week
2. **Cancellation & no-show rate**: by teacher and by cancel reason
3. **Net revenue per student**: purchases minus refunds
4. **Referral funnel**: invited → trial → converted (and expired)

Source tables (Postgres schema `app`): `teachers`, `students`,
`class_bookings`, `payments`, `referrals`. The database and the data generator
live in the source repo (`source-stock-data-pipeline/`) (fake data only).

---

## 2. Architecture

```
Local Postgres 16 (Docker, wal_level=logical)          ../source-stock-data-pipeline
   │  Pinggy TCP tunnel (make tunnel)
   ▼
AWS DMS  dms.t3.small, full load + CDC                  modules/ingestion/dms
   ▼
S3 Raw   raw/app/<table>/YYYY/MM/DD/*.parquet           modules/storage/s3_raw
   │  S3 ObjectCreated (.parquet) notification
   ▼
SQS stock-raw-events  (+ DLQ after 5 tries)             modules/ingestion/s3_athena_trigger
   │
   │   EventBridge Scheduler, rate(1 hour)              modules/orchestration/pipeline_run
   │        ▼
   │   Step Functions  tutoring-pipeline-run
   │   ┌──────────────────────────────────────────────────────────────────┐
   └──►│ 1 RawToBronze   trigger Lambda {"drain": true}                   │
       │    for each queued file:                                         │
       │      catalog_manager Lambda → Raw Glue table from the file schema │
       │      Athena INSERT INTO Bronze Iceberg (append-only)             │
       │    loops while the Lambda ran short on time (max 10)             │
       │                                                                  │
       │ 2 BronzeToSilver  only if ≥1 file loaded                         │
       │    ECS Fargate task (1 vCPU / 3 GB), Spark local mode            │
       │      read Bronze rows added since the last run (Iceberg snapshots)│
       │      keep the latest event per key                               │
       │      DQ rules per table                                          │
       │        good → MERGE INTO Silver Iceberg (insert/update/delete)   │
       │        bad  → quarantine bucket (parquet) → Athena tables        │
       │                                                                  │
       │ 3 Silver → Gold   dbt-athena                         (NEXT)      │
       └──────────────────────────────────────────────────────────────────┘
                 then: stream Gold to an external tool          (AFTER)
```

### Layers

| Layer | Where | Format | Written by |
|---|---|---|---|
| Raw | `s3://stock-raw-unique-12345/raw/app/<table>/` | DMS parquet (`Op`, `dms_ts`, source columns, `dms_change_seq`) | DMS |
| Bronze | Glue DB `stock_bronze`, `s3://stock-bronze-unique12345/iceberg/` | Iceberg, append-only: every I/U/D event + `source_file`, `ingested_at` | trigger Lambda via Athena |
| Silver | Glue DB `stock_silver`, `s3://stock-silver-unique123/iceberg/` | Iceberg, 1 row per key (current state) | Spark job (MERGE) |
| Quarantine | `s3://tutoring-quarantine-unique12345/<table>/window=<start>_<end>/`, Glue DB `stock_quarantine` | parquet + `dq_errors`, `run_id`, `quarantined_at`; expires after 30 days | Spark job |
| Gold | Glue DB `stock_gold` (empty) | — | dbt-athena (next) |

The Silver job records each run in `stock_silver.etl_control`: table, Bronze
snapshot window, events read, good rows and bad rows.

---

## 3. Repository layout

```
pipeline-infra/
├── main.tf  variables.tf  outputs.tf  providers.tf  versions.tf   root module: wires module outputs into module inputs
└── modules/
    ├── vpc_config/                     VPC + public subnets (no NAT gateway)
    ├── storage/
    │   ├── s3_raw/  s3_bronze/  s3_silver/  s3_quarantine/
    ├── ingestion/
    │   ├── dms/                        replication instance, endpoints, task (app.% tables)
    │   └── s3_athena_trigger/          S3 → SQS (+DLQ), trigger Lambda (lambda_function.py)
    ├── trans_layer/
    │   ├── glue_data_catalog/          Glue DBs stock_raw / stock_bronze / stock_silver / stock_gold / stock_quarantine
    │   ├── athena/                     workgroup, Bronze table DDL (tables.tf), quarantine tables (quarantine.tf)
    │   ├── lambda_trans/               catalog_manager Lambda (container image in ECR)
    │   └── spark_ecs/                  Spark job: ECR image, ECS cluster + task definition, IAM
    │       └── jobs/
    │           ├── Dockerfile          python 3.11 + Java 17 + PySpark 3.5.4 + Iceberg 1.6.1 + hadoop-aws
    │           ├── bronze_to_silver.py job: args, read window, MERGE, quarantine, control table
    │           ├── transforms.py       pure functions: dedup, DQ rules, MERGE SQL
    │           └── tests/              pytest (15 tests, incl. real Iceberg MERGE)
    └── orchestration/
        └── pipeline_run/               Step Functions state machine + EventBridge Scheduler
```

---

## 4. Deploy, run, destroy

Terraform runs **in the DevPod** (Linux devcontainer), not from the Windows host.

### Before you start
1. Start the source database and the tunnel (in the source repo (`source-stock-data-pipeline/`)):
   ```bash
   make up        # Postgres + generator
   make tunnel    # Pinggy: prints host + port; free URLs change every session
   ```
2. Set the variables. They have no defaults, and nothing secret goes in the code:
   ```bash
   export TF_VAR_source_host=<pinggy host>
   export TF_VAR_source_port=<pinggy port>
   export TF_VAR_database_password=<POSTGRES_PASSWORD from the source .env>
   ```

### Deploy
```bash
terraform init
terraform plan -out tfplan     # tfplan is git-ignored: it contains the password
terraform apply tfplan
```
Terraform also builds both Docker images (catalog_manager and the Spark job)
and pushes them to ECR. The first Spark image build takes about 10 minutes.

**Start DMS after apply.** The task is created stopped
(`start_replication_task = false` in `modules/ingestion/dms/task.tf`):
```bash
aws dms start-replication-task --start-replication-task-type start-replication \
  --replication-task-arn "$(aws dms describe-replication-tasks \
     --filters Name=replication-task-id,Values=stock-pipeline-replication \
     --query 'ReplicationTasks[0].ReplicationTaskArn' --output text)"
```
The source DB then shows an **active** replication slot
(`SELECT slot_name, active FROM pg_replication_slots;`).

### Run
The schedule starts a run every hour; the first one comes 1 hour after apply.
To start one now:
```bash
aws stepfunctions start-execution \
  --state-machine-arn "$(terraform output -raw pipeline_state_machine_arn)"
```

| Run ends in | Meaning |
|---|---|
| `Done` | files loaded to Bronze and the Spark job finished |
| `NoNewData` | queue was empty; no Spark task was started ($0) |
| `SkipBusy` | another run was still going |
| `RawToBronzeFailed` / `RawFilesFailed` | the trigger Lambda failed / some Raw files failed (they retry next run, then go to the DLQ) |
| `BronzeToSilverFailed` | Spark task failed or hit the 30-minute timeout; logs in `terraform output spark_log_group_name` |

### Destroy
```bash
terraform destroy
```
Everything is set to be removed, even when it isn't empty: buckets
(`force_destroy`), ECR repos (`force_delete`), Docker images (local and remote),
IAM roles (`force_detach_policies`), the Athena workgroup, and the log groups.
Also delete the DMS replication slot on the source DB afterwards: an
abandoned slot keeps WAL and fills the disk.

---

## 5. Bronze → Silver job

1. **Incremental read.** Bronze rows appended between the last processed
   Iceberg snapshot (from `etl_control`) and the current one. This is exact even
   when two loads commit out of order, unlike filtering on `ingested_at`.
2. **Latest event per key.** Ordered by `dms_ts` desc, then `dms_change_seq`
   desc. This handles two updates of the same row in one transaction (same commit
   time, different change sequence).
3. **Data quality.** Each rule is a Spark column expression; failed rule names
   are collected in `dq_errors`. A rule that evaluates to NULL counts as failed.
   Delete events only need the base rules.
4. **MERGE into Silver.** An event is applied only if it is the same age or newer
   than the Silver row, so re-running a window changes nothing. A delete removes
   the row. A bad latest event leaves the Silver row unchanged.
5. **Quarantine.** Bad rows are written to `window=<start>_<end>/` with mode
   overwrite, so a re-run doesn't duplicate them.
6. **Schema changes.** A new source column is added to Bronze by the trigger
   Lambda (`ALTER TABLE ADD COLUMNS`) and to Silver by the job. A changed column
   type stops the file on purpose.

### DQ rules (`jobs/transforms.py`, copied from the source `CHECK` constraints)

| Table | Rules |
|---|---|
| all | key not null, `op` in I/U/D, `dms_ts` not null, `created_at` / `updated_at` not null |
| teachers | full_name, country not null; `email_valid`; `hourly_rate_positive`; status in active/inactive |
| students | full_name, country not null; `email_valid`; plan in trial/basic/premium; status in active/paused/churned; `not_self_referred` |
| class_bookings | student/teacher/scheduled_at not null; duration 25 or 50; status allowed; cancel_reason allowed and set **only** when cancelled |
| payments | student_id not null; type purchase/refund; plan basic/premium; `amount_positive`; `currency_3_letters` (`^[A-Z]{3}$`); `refund_of` set only for refunds |
| referrals | referrer_id not null; `referee_email_valid`; status allowed; referee_id set once trial/converted |

The source database already enforces most of these with CHECK constraints, so
from the source only the email, currency and referee email formats can fail.
The rest catch data that the **pipeline itself** breaks (a bad cast, a wrong
column mapping, a truncated file).

### Reading the bad rows (Athena, workgroup `stock-pipeline-workgroup`)
```sql
-- every bad student row, newest first
SELECT student_id, email, dq_errors, run_id, quarantined_at
FROM stock_quarantine.students
ORDER BY quarantined_at DESC;

-- which rules fail most
SELECT rule, count(*) AS bad_rows
FROM stock_quarantine.payments CROSS JOIN UNNEST(dq_errors) AS t(rule)
GROUP BY rule ORDER BY bad_rows DESC;

-- which run window a row came from
SELECT payment_id, currency, "$path" FROM stock_quarantine.payments;
```
Or download them: `aws s3 cp s3://tutoring-quarantine-unique12345/students/ ./q --recursive`.

---

## 6. Testing

### Unit + Iceberg tests (run inside the job image, ~1 min)
```bash
cd modules/trans_layer/spark_ecs/jobs
docker build -t spark-job-test:local .
docker run --rm --user root -v "$(pwd -W)":/src:ro \
  -e ICEBERG_JAR=/usr/local/lib/python3.11/site-packages/pyspark/jars/iceberg-spark-runtime-3.5_2.12-1.6.1.jar \
  --entrypoint bash spark-job-test:local \
  -c "cp -r /src /tmp/t && cd /tmp/t && pip install -q pytest==8.3.3 && python -m pytest -q tests"
```
(`$(pwd -W)` is for Git Bash on Windows; use `$(pwd)` on Linux.) Result: 15 passed.

### End-to-end DQ test against the real pipeline
In the source repo (`source-stock-data-pipeline/`):
```bash
docker exec -i tutoring-source-db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < scripts/dq_test_changes.sql
```

| Case | Change | Expected |
|---|---|---|
| 1 | student insert + 2 updates in one transaction | Silver: 1 row, plan `premium` |
| 2 | student email without `@` | quarantine `[email_valid]` |
| 3 | valid student "DQ Test Held" | Silver: 1 row |
| 4 | payment currency `usd` | quarantine `[currency_3_letters]` |
| 5 | referral email without `@` | quarantine `[referee_email_valid]` |
| 6 | cancelled booking inserted then deleted | nothing in Silver or quarantine |
| 7 | `plan='gold'`, `amount=-5` | rejected by the database itself |

Run `scripts/dq_test_changes_step2.sql` **after** the first pipeline run. It
breaks case 3's email; Silver must keep the old row and quarantine gets the update.

Need more data? Run a burst of about 300 changes:
`docker exec tutoring-generator python simulate.py --iterations 30 --actions-per-tick 10 --sleep 0.2`

**Result on 2026-11-22:** run SUCCEEDED; quarantine held exactly students
271/331, payments 196/245 and referrals 115/141, with the expected rule names.

---

## 7. Cost

| Item | Cost |
|---|---|
| DMS `dms.t3.small` | the main cost while it exists (billed hourly, can't be stopped) → **destroy after use** |
| Spark on Fargate | about $0.005 per 5-minute run, only when new data arrived; $0 between runs |
| Lambda, SQS, Step Functions, Scheduler, Glue Catalog | inside the free tier at this volume |
| Athena | per data scanned; tiny tables |
| ECR | Spark image about 1 GB (> 500 MB free) → about $0.10 per GB-month; repo keeps the last 2 images |
| S3 | a few MB; quarantine expires after 30 days |

Not used on purpose: NAT gateway (Fargate gets a public IP instead), EMR
(account vCPU quota is 0), Glue jobs, Glue crawlers, Kinesis, Redshift.

---

## 8. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| ECS shows no tasks | Normal: there is no ECS service. A task only runs during a pipeline run that loaded new files. Check the **Stopped** filter, then `aws stepfunctions get-execution-history`; the RawToBronze output shows `{loaded, skipped, failed}`. |
| Run ends `NoNewData` but data was changed | DMS hasn't written the CDC file yet, or the DMS task / Pinggy tunnel is down. Check `ApproximateNumberOfMessages` on `stock-raw-events`. |
| `not authorized to create managed-rule` on apply | The Step Functions role's policy must exist before the state machine (fixed with `depends_on`). If it still fails once, IAM is propagating; run apply again. |
| `EntityAlreadyExists` / subnet group exists on apply | Leftovers from an older lost state → `terraform import` them, or delete them. |
| EMR `exceeded the maximum concurrent vCPUs` | Account quota is 0; that's why Spark runs on ECS Fargate. |
| DMS `server closed the connection unexpectedly` | The free tunnel drops parallel connections during full load. Fix: `FullLoadSettings.MaxFullLoadSubTasks = 1` in `replication_task_settings` (`dms/task.tf`). **Not currently set** (it was lost from the file); the 2026-11-22 full load worked without it. |
| `dms.t3.micro` not orderable | Not available in us-east-1; use `dms.t3.small`. |
| Messages "in flight" for 30 minutes | A failed file stays invisible for the visibility timeout, then retries; after 5 tries it goes to the DLQ. |
| Source disk growing | An inactive replication slot is holding WAL → `SELECT pg_drop_replication_slot('<name>')` once you've confirmed DMS doesn't use it. |

---

## 9. Design decisions (short)

- **CDC, not snapshots:** hard deletes (cancelled bookings) are invisible to daily snapshots.
- **Bronze is append-only:** every event is kept for replay and audit; the MERGE happens only in Silver.
- **Scheduled drain, not one Lambda per file:** one load at a time means no Iceberg commit conflicts, and idle hours cost $0. Trade-off: up to 1 hour of latency.
- **Own PySpark DQ rules, not Glue Data Quality:** row-level results only work inside Glue jobs (paid DPUs); our rules run in the same Spark job and are unit-tested.
- **Spark on ECS Fargate, not EMR Serverless:** the EMR vCPU quota is 0; same code, per-second billing, nothing left running.
- **Quarantine as unpartitioned Athena tables:** Athena reads every `window=` subfolder, so there's no crawler and no partition upkeep.
- **Terraform only:** no shell scripts. `apply` builds everything including images; `destroy` removes everything.

## 10. Roadmap

- [x] Source DB + generator, DMS full load + CDC to Raw
- [x] Raw → Bronze Iceberg (SQS, Lambdas, Athena)
- [x] Bronze → Silver Spark job with DQ, MERGE, quarantine + 15 tests
- [x] Step Functions + hourly schedule, Terraform-only deploy/destroy
- [x] First successful end-to-end run on AWS (2026-11-22)
- [ ] Apply: quarantine Athena tables + Step Functions failure-path fix
- [ ] **Silver → Gold:** dbt-athena, 4 models + dbt tests, as a Step Functions step
- [ ] **Stream Gold to an external tool** (tool to be chosen)
- [ ] CI (pytest on push), AWS Budget alert, screenshots, final `terraform destroy`
