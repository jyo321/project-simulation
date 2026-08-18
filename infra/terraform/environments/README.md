# Per-environment `.tfvars`

One file per Terraform workspace, holding the values that should genuinely differ between
`dev`/`staging`/`prod` (instance sizing, task CPU/memory, VPC CIDR) — anything that's the
same everywhere belongs in `variables.tf`'s defaults instead, not duplicated three times here.

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
override (see `github_oidc.tf`'s header comment), and putting it in a file that gets
applied to every environment is exactly the mistake that variable exists to prevent. Pass
it as an explicit `-var` only when you mean it, in the one workspace you're bootstrapping
shared resources from.

The VPC CIDRs below are deliberately non-overlapping across the three environments —
harmless today, but it means you can VPC-peer or Transit-Gateway any two of them later
without a re-address.
