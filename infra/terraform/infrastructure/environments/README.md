# Per-environment `.tfvars`

One file per Terraform workspace. Every variable declared in `variables.tf` gets an
explicit value here for every environment — including ones that happen to be identical
across all four (`aws_region`, `db_name`, ...) — so each file is a complete, self-contained
picture of that environment's configuration, not just a diff against some implicit default
you'd have to go read `variables.tf` to find. The two deliberate exceptions are below.

`uat` is sized like `staging` (not a load-test target) but matches `prod`'s API task
CPU/memory on purpose — it exists for behavior sign-off, so it should behave like prod for
whoever's testing it, not be scaled down the way `dev`/`staging` are for cost.

**`db_password` is deliberately never in these files.** They're committed to git; a
database password isn't. Always supply it separately, at apply time:

```bash
terraform workspace select dev
terraform apply -var-file="environments/dev.tfvars" -var="db_password=$TF_VAR_db_password"
```

(or export `TF_VAR_db_password` and drop the `-var` entirely — Terraform picks up
`TF_VAR_*` env vars automatically). In CI, `DB_PASSWORD` comes from the `infra-ci-cd.yml`
workflow's GitHub secret the same way, never from a file.

`create_shared_resources` is deliberately absent too — it's a one-time, single-workspace
override (see `modules/github_oidc/main.tf`'s header comment), and putting it in a file that gets
applied to every environment is exactly the mistake that variable exists to prevent. Pass
it as an explicit `-var` only when you mean it, in the one workspace you're bootstrapping
shared resources from.

The VPC CIDRs below are deliberately non-overlapping across all four environments —
harmless today, but it means you can VPC-peer or Transit-Gateway any two of them later
without a re-address.

**Your editor's Terraform extension will likely flag every attribute in these files as
"unexpected"/"not expected here" — that's a false alarm, not a real error.** Its language
server resolves a `.tfvars` file's variables against whatever module lives in the *same
directory*, and since the `variable` blocks live one level up in
`infra/terraform/infrastructure/*.tf`, not here, it can't see any declarations at all from
this folder's point of view. The actual Terraform CLI has no such restriction —
`-var-file` accepts a path to anywhere — and `terraform plan -var-file="environments/dev.tfvars"`
(run from `infra/terraform/infrastructure/`) resolves every value correctly.
