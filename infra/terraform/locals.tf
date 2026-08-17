# The active Terraform workspace IS the environment — `terraform workspace select prod`
# (or `terraform workspace new prod` the first time) is what picks it. There's no separate
# -var to keep in sync with your workspace; every environment-scoped resource name below
# derives from local.environment, so switching workspaces is the entire act of switching
# environments.
#
# Never apply real resources from the "default" workspace (the one that exists before you
# create any named one) — always create dev/staging/prod explicitly first, since
# "default" makes a confusing environment label to find in the AWS console later.
locals {
  environment = terraform.workspace
}
