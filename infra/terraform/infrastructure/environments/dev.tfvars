aws_region         = "us-east-2"
availability_zones = ["us-east-2a", "us-east-2b", "us-east-2c"]

github_repo = "jyo321/project-simulation"

vpc_cidr = "10.20.0.0/16"

db_name     = "northbridge"
db_username = "northbridge_app"

# Smallest RDS class that still runs Postgres 16 comfortably for a dev workload.
db_instance_class = "db.t4g.micro"

# Disposable environment: no Multi-AZ standby to pay for, and deletion protection off so
# `terraform destroy` (see README's "Known gotchas") actually tears it down.
db_multi_az            = false
db_deletion_protection = false

# Half the prod API task size — dev traffic doesn't need it, and it's the cost that scales
# with desired_count (2 tasks per API) most directly.
api_task_cpu    = 256
api_task_memory = 512

# Fire-and-forget jobs still need real headroom to exercise the same code path prod runs,
# just not prod's full allocation.
fire_and_forget_task_cpu    = 1024
fire_and_forget_task_memory = 4096

# Same report logic, faster feedback loop while poking at it by hand.
stale_after_days = 1

# Placeholder domain nobody owns — SES can't send until this is a verified identity.
# Override with a real address when you actually wire up notifications for this environment.
notification_sender_email = "notifications@northbridgelending.com"

# CI overwrites the running image out-of-band after the first deploy (see the
# `ignore_changes` lifecycle blocks in ecs.tf/lambda.tf) — this only matters for the very
# first apply in a brand-new workspace, before any image has been pushed.
container_image_tag = "latest"
