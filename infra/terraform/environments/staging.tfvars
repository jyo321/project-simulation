github_repo = "jyo321/project-simulation"

vpc_cidr = "10.21.0.0/16"

# One tier up from dev — enough headroom to load-test against, not full prod cost.
db_instance_class = "db.t4g.small"

api_task_cpu    = 512
api_task_memory = 1024

fire_and_forget_task_cpu    = 2048
fire_and_forget_task_memory = 8192

stale_after_days = 3
