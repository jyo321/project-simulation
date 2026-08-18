aws_region         = "us-east-1"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

github_repo = "jyo321/project-simulation"

vpc_cidr = "10.21.0.0/16"

db_name     = "northbridge"
db_username = "northbridge_app"

# One tier up from dev — enough headroom to load-test against, not full prod cost.
db_instance_class = "db.t4g.small"

# Disposable environment, same reasoning as dev.tfvars.
db_multi_az            = false
db_deletion_protection = false

api_task_cpu    = 512
api_task_memory = 1024

fire_and_forget_task_cpu    = 2048
fire_and_forget_task_memory = 8192

stale_after_days = 3

notification_sender_email = "notifications@northbridgelending.com"
container_image_tag       = "latest"
