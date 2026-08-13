# Northbridge Lending

A reference implementation of the Platform/DevOps team's cloud architecture brief: a
digital loan application & approval platform on AWS. See **[docs/architecture.md](docs/architecture.md)**
for the full written deliverable (service mapping, diagram, security/networking, CI/CD,
and explicit answers to every question in the brief).

## What's here

| Path | What it is | Maps to brief |
|---|---|---|
| [`frontend/applicant-portal`](frontend/applicant-portal) | Angular 17 CSR SPA — borrowers apply, upload docs, track status | §2.1, SPA #1 |
| [`frontend/reviewer-console`](frontend/reviewer-console) | Angular 17 CSR SPA — underwriters review & decide | §2.1, SPA #2 |
| [`backend/Applications.Api`](backend/Applications.Api) | .NET 8 API — applicants, loan applications, submit | §2.2, API #1 |
| [`backend/Documents.Api`](backend/Documents.Api) | .NET 8 API — pre-signed S3 upload/download, document confirm | §2.2, API #2 |
| [`backend/Decisioning.Api`](backend/Decisioning.Api) | .NET 8 API — reviewer queue, approve/reject | §2.2, API #3 |
| [`backend/Northbridge.Shared`](backend/Northbridge.Shared) | EF Core entities/DbContext + AWS client abstractions shared by every service | — |
| [`workers/DocumentValidationWorker`](workers/DocumentValidationWorker) | Service-triggered (SQS) | §2.3.1, worker #1 |
| [`workers/StatusProjectorWorker`](workers/StatusProjectorWorker) | Service-triggered (SNS→SQS) | §2.3.1, worker #2 |
| [`workers/DailyStaleReportJob`](workers/DailyStaleReportJob) | Time-based (EventBridge Scheduler cron), Postgres advisory lock | §2.3.2 |
| [`workers/CreditScoringJob`](workers/CreditScoringJob) | Fire-and-forget, >20 min, ECS RunTask | §2.3.3, job #1 |
| [`workers/FraudForensicsJob`](workers/FraudForensicsJob) | Fire-and-forget, >20 min, ECS RunTask | §2.3.3, job #2 |
| [`notification-service/NotificationWorker`](notification-service/NotificationWorker) | Retry + backoff + DLQ, SES/SNS | §2.6 |
| [`infra/terraform`](infra/terraform) | VPC, RDS, S3, SQS/SNS/EventBridge, ECS/ALB, ECR, CloudFront, IAM, Secrets Manager | §3/§8 |
| [`docker-compose.yml`](docker-compose.yml) + [`scripts/localstack-init`](scripts/localstack-init) | Runs the whole system locally against LocalStack — no AWS account needed | — |
| [`.github/workflows`](.github/workflows) | Frontend / API / workers / infra pipelines | §9 |

## Running it locally

Requires Docker, Node 20+, and the .NET 8 SDK.

```bash
# 1. Bring up Postgres, LocalStack (S3/SQS/SNS/SES), the 3 APIs, and the 3 standing-service
#    background workers.
docker compose up --build

# 2. Run either SPA against the local APIs.
cd frontend/applicant-portal && npm install && npm start   # http://localhost:4200
cd frontend/reviewer-console && npm install && npm start   # http://localhost:4201
```

The three fire-and-forget/scheduled jobs (`daily-stale-report-job`, `credit-scoring-job`,
`fraud-forensics-job`) are modeled as one-shot containers, matching how they really run in
AWS (`ecs:RunTask`, not a standing service) — not something `docker compose up` starts.
Trigger one manually, e.g. after submitting an application and grabbing its `jobId` from the
API response:

```bash
docker compose run --rm \
  -e JOB_ID=<job-id-from-submit-response> \
  -e LOAN_APPLICATION_ID=<application-id> \
  credit-scoring-job
```

Applications.Api applies EF Core migrations on startup (see `Program.cs`), so the schema is
created automatically the first time the stack comes up.

## Deploying to AWS

```bash
cd infra/terraform
terraform init
terraform plan  -var="db_password=<secret>" -var="acm_certificate_arn=<your-acm-cert>"
terraform apply -var="db_password=<secret>" -var="acm_certificate_arn=<your-acm-cert>"
```

This provisions the VPC, RDS, S3 buckets, SQS/SNS/EventBridge topology, ECS cluster/ALB,
ECR repositories, and the two CloudFront distributions. It does **not** push any container
images — run the CI/CD workflows (or `docker build`/`docker push` by hand) against the ECR
repos Terraform creates before the ECS services can start healthy.

## Local dev vs. AWS — what actually differs

Nothing in the application code. Every service talks to AWS through the SDK's normal
client interfaces; `docker-compose.yml` simply points those clients at LocalStack via
`AWS__DefaultClientConfig__ServiceURL` instead of the real regional endpoints, and supplies
dummy credentials LocalStack accepts unconditionally. Swapping that environment block for
real AWS credentials and endpoints is the entire difference between "running on a laptop"
and "running in the account Terraform provisioned."
