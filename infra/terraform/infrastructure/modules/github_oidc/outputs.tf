output "github_actions_deploy_role_arn" {
  value = try(aws_iam_role.github_actions_deploy[0].arn, "not created in this workspace — see create_shared_resources")
}

output "github_actions_terraform_role_arn" {
  value = try(aws_iam_role.github_actions_terraform[0].arn, "not created in this workspace — see create_shared_resources")
}
