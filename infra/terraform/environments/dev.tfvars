github_repo = "jyo321/project-simulation"

vpc_cidr = "10.20.0.0/16"

# Smallest RDS class that still runs Postgres 16 comfortably for a dev workload.
db_instance_class = "db.t4g.micro"

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
