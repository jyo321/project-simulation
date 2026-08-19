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
| [`workers/DailyStaleReportJob`](workers/DailyStaleReportJob) | Time-based (EventBridge Scheduler cron → Lambda), Postgres advisory lock | §2.3.2 |
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

The two fire-and-forget jobs (`credit-scoring-job`, `fraud-forensics-job`) are modeled as
one-shot containers, matching how they really run in AWS (`ecs:RunTask`, not a standing
service) — not something `docker compose up` starts. Trigger one manually, e.g. after
submitting an application and grabbing its `jobId` from the API response:

```bash
docker compose run --rm \
  -e JOB_ID=<job-id-from-submit-response> \
  -e LOAN_APPLICATION_ID=<application-id> \
  credit-scoring-job
```

`daily-stale-report-job` runs as AWS Lambda in real AWS, so its image is built FROM
`public.ecr.aws/lambda/dotnet`, which bundles the Lambda Runtime Interface Emulator —
start it like a service and invoke it with a curl POST instead of `docker compose run`:

```bash
docker compose up -d daily-stale-report-job
curl -XPOST http://localhost:9000/2015-03-31/functions/function/invocations -d '{}'
```

Applications.Api applies EF Core migrations on startup (see `Program.cs`), so the schema is
created automatically the first time the stack comes up.

## Deploying to AWS

### 0. One-time: bootstrap remote state

`infra/terraform/infrastructure` stores its state in S3 (locking included —
Terraform 1.10+'s S3 backend locks via S3's own conditional writes, no DynamoDB table
needed) so that both your machine and the ephemeral GitHub Actions runners share the same
state instead of each starting from blank. That S3 bucket has to exist *before*
`infrastructure` can initialize — and an apply can't store its own state in a bucket that
same apply is creating — so bucket creation lives in its own small, standalone Terraform
project, `infra/terraform/bootstrap`, applied once by hand with plain local state:

```bash
cd infra/terraform/bootstrap
terraform init
terraform apply -var="state_bucket_name=northbridge-tfstate-<your-account-id>"
```

Then put that same bucket name into `infra/terraform/infrastructure/backend.tf`'s
`backend "s3"` block (replace `REPLACE-WITH-YOUR-ACCOUNT-ID`) and initialize it there:

```bash
cd ../infrastructure
terraform init
```

Run the bootstrap apply once, ever, per AWS account — not per environment. Nothing else
in this guide ever touches `bootstrap/` again.

### 1. Workspaces = environments

`infra/terraform/infrastructure` uses **Terraform workspaces** to run
`dev`/`staging`/`uat`/`prod` side by side in the same AWS account without name
collisions — every environment-scoped resource (RDS instance, S3 buckets, SQS/SNS, ECR
repos, ECS cluster/services, IAM task roles, ALB target groups, ...) is suffixed with
`local.environment`, which is just `terraform.workspace`
(`infra/terraform/infrastructure/locals.tf`). There's no `-var=environment` to remember to
set — whichever workspace is selected *is* the environment.

```bash
cd infra/terraform/infrastructure
terraform workspace new dev       # or: terraform workspace select dev
```

**Per-environment sizing lives in `.tfvars`, not on the command line.**
`infra/terraform/infrastructure/environments/{dev,staging,uat,prod}.tfvars` hold
everything that should genuinely differ between environments — RDS instance class, ECS
task CPU/memory, VPC CIDR (non-overlapping across all four, so any two can be peered
later without a re-address) — see
`infra/terraform/infrastructure/environments/README.md`. `db_password` is deliberately
**not** in any of them (they're committed to git); always pass it separately, e.g. via
`TF_VAR_db_password`.

**Every new environment needs one extra step before its first full apply.** Everything
in this stack is ECS-based except `DailyStaleReportJob`, which runs as a Lambda
container image (`infra/terraform/infrastructure/modules/lambda`) — and unlike an ECS
task definition, Lambda validates at creation time that its image already exists in ECR.
On a brand-new workspace the ECR repo is empty, so a straight `terraform apply` fails on
that one resource. Create just the ECR repos first, seed that one repo with a real image,
then apply everything else:

```bash
export TF_VAR_db_password=<secret>
terraform apply -target=module.ecr.aws_ecr_repository.service -var-file="environments/dev.tfvars"

aws ecr get-login-password --region us-east-2 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-2.amazonaws.com
docker build -f workers/DailyStaleReportJob/Dockerfile \
  -t <account-id>.dkr.ecr.us-east-2.amazonaws.com/northbridge/dev/daily-stale-report-job:latest .
docker push <account-id>.dkr.ecr.us-east-2.amazonaws.com/northbridge/dev/daily-stale-report-job:latest

terraform plan  -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/dev.tfvars"
```

(`northbridge/dev/...` and `environments/dev.tfvars` above assume the `dev` workspace —
swap for whichever workspace you're applying.) After this first apply, `workers-ci-cd.yml`
keeps that Lambda's code up to date on every push — you only do this manual seed once,
the first time a given environment is created.

Repeat the whole sequence (`terraform workspace new staging` / `uat` / `prod`, matching
`.tfvars` file, ECR seed, apply) to stand up the other environments — each gets its own
VPC, database, buckets, queues, and ECS cluster.

**Account-wide resources are the one exception.** The GitHub OIDC provider and the two
CI/CD IAM roles (`infra/terraform/infrastructure/modules/github_oidc`) are IAM objects whose *names* are
unique per AWS account, not per workspace — every workspace trying to create them would
collide on the second apply. They're gated behind `create_shared_resources` (default
`false`); set `-var="create_shared_resources=true"` in **exactly one** workspace, ever
(pick whichever you consider authoritative, e.g. `prod`). This one is intentionally kept
out of the `.tfvars` files — it's a one-time override, not per-environment sizing:

```bash
terraform workspace select prod
terraform apply -var-file="environments/prod.tfvars" -var="create_shared_resources=true"
```

This provisions, per workspace: the VPC, RDS, S3 buckets, SQS/SNS/EventBridge topology,
ECS cluster/ALB, ECR repositories, and the two CloudFront distributions. It does **not**
push any container images — that's what the CI/CD pipelines below are for.

Notice there's no `acm_certificate_arn` or domain anywhere: each CloudFront distribution
fronts both its S3 bucket *and* the ALB (see `infra/terraform/infrastructure/modules/cloudfront_frontend`),
terminating HTTPS with CloudFront's own free default certificate. Each environment is
reachable from its own CloudFront URL alone — `terraform output applicant_portal_cloudfront_domain`
/ `reviewer_console_cloudfront_domain` — no domain purchase or Route 53 record required.

### Known gotchas on a real account

- **S3 bucket names aren't guaranteed free.** The 5 buckets this stack creates
  (`northbridge-raw-documents-<env>`, `-generated-documents-`, `-reports-`,
  `-applicant-portal-`, `-reviewer-console-`) are only suffixed by environment, not by
  account ID — S3's bucket namespace is global across every AWS account, so on the
  (unlikely but possible) chance one of these exact names is already taken by someone
  else, `terraform apply` fails on that resource with `BucketAlreadyExists`. Fix by
  editing the bucket name in `modules/s3_documents/main.tf` / `modules/cloudfront_frontend/main.tf`
  and re-applying.
- **SES starts in sandbox mode.** `NotificationWorker` sends real email via SES, but
  Terraform doesn't provision domain/email verification. Until you verify a sender
  identity in the SES console (and, while still in sandbox, verify recipients too, or
  request production access), notifications will fail at send time — the rest of the
  app is unaffected. Override `-var="notification_sender_email=<a verified address>"`;
  the placeholder default (`notifications@northbridgelending.com`) is a domain you
  don't own and can't verify.
- **This isn't free-tier.** RDS Multi-AZ, a NAT Gateway, an ALB, and several interface
  VPC endpoints all bill by the hour regardless of traffic — expect real (if modest,
  low tens of USD/month per environment) cost the moment `apply` finishes, not just
  when the app is used. `terraform destroy` when you're done experimenting.

## CI/CD (GitHub Actions)

Yes — deployment after the initial `terraform apply` above is fully automated. Four
pipelines in [`.github/workflows`](.github/workflows), matching the brief's requirement
that each deployable piece ships independently:

| Workflow | Triggers on | Does |
|---|---|---|
| `frontend-ci-cd.yml` | changes under `frontend/**` | builds each Angular app, syncs it to its own S3 bucket, invalidates its own CloudFront distribution — one app's release never touches the other's |
| `api-ci-cd.yml` | changes under `backend/**` | builds/tests each API, pushes a new image to its ECR repo, rolls its ECS service (zero-downtime, ECS's own rolling deployment) |
| `workers-ci-cd.yml` | changes under `workers/**`, `notification-service/**`, `backend/Northbridge.Shared/**` | same as above for the 5 workers + notification worker — standing workers get an ECS service roll, the 3 one-shot jobs just get a new task-definition revision (nothing to "roll" since they're not a service) |
| `infra-ci-cd.yml` | changes under `infra/terraform/infrastructure/**` | `terraform plan` on every PR and on push to `main`; `terraform apply` runs only after manual approval on the `infra-prod` GitHub environment — kept separate so an infra change never ships silently bundled with an app deploy |

**Authentication**: no long-lived AWS access keys stored in GitHub. `infra/terraform/infrastructure/modules/github_oidc`
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

**Targeting an environment.** All four workflows accept a `workflow_dispatch` input
named `environment` (Actions tab → pick the workflow → "Run workflow"), which becomes
`TARGET_ENV` and is threaded into every environment-scoped name the workflow touches —
the ECR image path (`northbridge/<env>/<image>`), the ECS cluster
(`northbridge-cluster-<env>`), and the task-definition family. It defaults to `prod` on
the automatic push-to-`main` trigger, so nothing changes for the common case; use a
manual dispatch to plan/apply or deploy against `dev`/`staging` instead. The value you
pass here must match a workspace you've already created in step 1 above — the infra
pipeline's `terraform workspace select "$TARGET_ENV" || terraform workspace new "$TARGET_ENV"`
step will create it if it doesn't exist yet, but the app pipelines (api/workers/frontend)
assume the ECR repos/ECS cluster for that environment already exist.

**Limitation — secrets are not per-environment.** `DB_PASSWORD` and the SPA
bucket/CloudFront IDs are single repo-level GitHub secrets, reused for whichever
environment a given run targets. That's fine as long as every environment shares one DB
password and you're comfortable a `dev` run and a `prod` run read the same secret
values; if you want per-environment secrets, move them into GitHub **environments**
(`dev`, `staging`, `uat`, `prod`) instead of repo-level secrets, and reference
`${{ vars.TARGET_ENV }}`-scoped environment secrets in each job.

## Local dev vs. AWS — what actually differs

Nothing in the application code. Every service talks to AWS through the SDK's normal
client interfaces; `docker-compose.yml` simply points those clients at LocalStack via
`AWS__DefaultClientConfig__ServiceURL` instead of the real regional endpoints, and supplies
dummy credentials LocalStack accepts unconditionally. Swapping that environment block for
real AWS credentials and endpoints is the entire difference between "running on a laptop"
and "running in the account Terraform provisioned."
