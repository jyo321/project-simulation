aws_region         = "us-east-1"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

github_repo = "jyo321/project-simulation"

vpc_cidr = "10.23.0.0/16"

db_name     = "northbridge"
db_username = "northbridge_app"

# Sized like staging, not prod — UAT is for functional sign-off against realistic behavior,
# not load testing, so it doesn't need prod's full capacity.
db_instance_class = "db.t4g.small"

# Matches prod's API sizing deliberately: UAT is meant to behave like prod for whoever's
# signing off on it, unlike dev/staging which are scaled down for cost.
api_task_cpu    = 512
api_task_memory = 1024

fire_and_forget_task_cpu    = 2048
fire_and_forget_task_memory = 8192

stale_after_days = 2

notification_sender_email = "notifications@northbridgelending.com"
container_image_tag       = "latest"
