aws_region         = "us-east-2"
availability_zones = ["us-east-2a", "us-east-2b", "us-east-2c"]

github_repo = "jyo321/project-simulation"

vpc_cidr = "10.22.0.0/16"

db_name     = "northbridge"
db_username = "northbridge_app"

db_instance_class = "db.t4g.medium"

api_task_cpu    = 512
api_task_memory = 1024

fire_and_forget_task_cpu    = 4096
fire_and_forget_task_memory = 16384

stale_after_days = 5

notification_sender_email = "notifications@northbridgelending.com"
container_image_tag       = "latest"
