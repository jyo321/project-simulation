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
terraform plan  -var="db_password=<secret>" -var="github_repo=<owner>/<repo>"
terraform apply -var="db_password=<secret>" -var="github_repo=<owner>/<repo>"
```

This provisions the VPC, RDS, S3 buckets, SQS/SNS/EventBridge topology, ECS cluster/ALB,
ECR repositories, and the two CloudFront distributions. It does **not** push any container
images — that's what the CI/CD pipelines below are for.

Notice there's no `acm_certificate_arn` or domain anywhere: each CloudFront distribution
fronts both its S3 bucket *and* the ALB (see `infra/terraform/cloudfront_frontend.tf`),
terminating HTTPS with CloudFront's own free default certificate. The whole system is
reachable from the CloudFront URL alone — `terraform output applicant_portal_cloudfront_domain`
/ `reviewer_console_cloudfront_domain` — no domain purchase or Route 53 record required.

## CI/CD (GitHub Actions)

Yes — deployment after the initial `terraform apply` above is fully automated. Four
pipelines in [`.github/workflows`](.github/workflows), matching the brief's requirement
that each deployable piece ships independently:

| Workflow | Triggers on | Does |
|---|---|---|
| `frontend-ci-cd.yml` | changes under `frontend/**` | builds each Angular app, syncs it to its own S3 bucket, invalidates its own CloudFront distribution — one app's release never touches the other's |
| `api-ci-cd.yml` | changes under `backend/**` | builds/tests each API, pushes a new image to its ECR repo, rolls its ECS service (zero-downtime, ECS's own rolling deployment) |
| `workers-ci-cd.yml` | changes under `workers/**`, `notification-service/**`, `backend/Northbridge.Shared/**` | same as above for the 5 workers + notification worker — standing workers get an ECS service roll, the 3 one-shot jobs just get a new task-definition revision (nothing to "roll" since they're not a service) |
| `infra-ci-cd.yml` | changes under `infra/terraform/**` | `terraform plan` on every PR and on push to `main`; `terraform apply` runs only after manual approval on the `infra-prod` GitHub environment — kept separate so an infra change never ships silently bundled with an app deploy |

**Authentication**: no long-lived AWS access keys stored in GitHub. `infra/terraform/github_oidc.tf`
provisions two IAM roles GitHub Actions assumes via OIDC, trusting only pushes to `main`
in this specific repo:
- a narrow **deploy role** (ECR push, ECS roll, S3 sync, CloudFront invalidate) — used by
  the frontend/api/workers pipelines
- a broad **terraform role** (full infra changes) — used only by `infra-ci-cd.yml`'s
  `apply` job, behind the manual-approval gate

**One-time setup** after the first `terraform apply`, before pushing to any of the
watched paths:
1. Settings → Environments → new environment `infra-prod` → add yourself as a required reviewer
2. Settings → Secrets and variables → Actions → add `AWS_ACCOUNT_ID`, `AWS_DEPLOY_ROLE_ARN`
   and `AWS_TERRAFORM_ROLE_ARN` (from `terraform output`), `DB_PASSWORD`, and the four
   `applicant_portal_bucket` / `applicant_portal_cloudfront_id` / `reviewer_console_bucket` /
   `reviewer_console_cloudfront_id` values (also from `terraform output`)

After that, `git push` to `main` is the entire deploy step — whichever pipelines match the
changed paths run on their own.

## Local dev vs. AWS — what actually differs

Nothing in the application code. Every service talks to AWS through the SDK's normal
client interfaces; `docker-compose.yml` simply points those clients at LocalStack via
`AWS__DefaultClientConfig__ServiceURL` instead of the real regional endpoints, and supplies
dummy credentials LocalStack accepts unconditionally. Swapping that environment block for
real AWS credentials and endpoints is the entire difference between "running on a laptop"
and "running in the account Terraform provisioned."
