# Tier-to-tier security group chain per docs/architecture.md §8:
#   internet -> sg-alb -> sg-ecs_app -> sg-rds
# Workers get their own sg-worker: egress-only, no ingress at all.

resource "aws_security_group" "alb" {
  name        = "northbridge-alb-sg"
  description = "Public HTTPS entry point"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from CloudFront / internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_app" {
  name        = "northbridge-ecs-app-sg"
  description = "The three request-serving APIs — only reachable from the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Container port from ALB only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_worker" {
  name        = "northbridge-ecs-worker-sg"
  description = "Background workers and fire-and-forget jobs — no ingress at all"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "northbridge-rds-sg"
  description = "Postgres — reachable only from the app tier and workers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from APIs"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_app.id]
  }

  ingress {
    description     = "Postgres from background workers"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_worker.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
