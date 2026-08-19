# Three-tier layout per docs/architecture.md §8: public (ALB/NAT), private-app (ECS),
# private-data (RDS, no NAT route at all).
#
# Security groups live here too (not their own module) because they're mutually
# referential with the VPC's own endpoint SG: the vpc_endpoints SG allows ingress from
# ecs_app's SG, and rds's SG allows ingress from ecs_app/ecs_worker — all four tiers are
# one coherent network unit per docs/architecture.md §8's sg chain.

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "northbridge-vpc-${var.environment}" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "northbridge-igw" }
}

resource "aws_subnet" "public" {
  for_each = { for idx, az in var.availability_zones : az => idx }

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value)
  map_public_ip_on_launch = true

  tags = { Name = "northbridge-public-${each.key}", Tier = "public" }
}

resource "aws_subnet" "private_app" {
  for_each = { for idx, az in var.availability_zones : az => idx }

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.value + 10)

  tags = { Name = "northbridge-private-app-${each.key}", Tier = "private-app" }
}

resource "aws_subnet" "private_data" {
  for_each = { for idx, az in var.availability_zones : az => idx }

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.value + 20)

  tags = { Name = "northbridge-private-data-${each.key}", Tier = "private-data" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "northbridge-nat-eip" }
}

# Single NAT gateway keeps the reference build cheap; a production deployment would run
# one per AZ for NAT-tier HA.
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.public)[0].id
  tags          = { Name = "northbridge-nat" }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "northbridge-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "northbridge-private-app-rt" }
}

resource "aws_route_table_association" "private_app" {
  for_each = aws_subnet.private_app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_app.id
}

# No internet route at all for the data tier — not even via NAT.
resource "aws_route_table" "private_data" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "northbridge-private-data-rt" }
}

resource "aws_route_table_association" "private_data" {
  for_each = aws_subnet.private_data

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_data.id
}

# Gateway + interface VPC endpoints keep S3/SQS/SNS/Secrets Manager/ECR traffic off the
# public internet and off the NAT gateway's per-GB charge.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_app.id]
}

resource "aws_vpc_endpoint" "interface_endpoints" {
  for_each = toset(["sqs", "sns", "secretsmanager", "ecr.api", "ecr.dkr"])

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private_app : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "northbridge-vpc-endpoints-sg"
  description = "Allows the app tier to reach interface VPC endpoints over TLS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# Tier-to-tier security group chain per docs/architecture.md §8:
#   internet -> sg-alb -> sg-ecs_app -> sg-rds
# Workers get their own sg-worker: egress-only, no ingress at all.
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "northbridge-alb-sg"
  description = "HTTP entry point — reachable only meaningfully via CloudFront, which holds the X-Origin-Verify secret every listener rule requires (modules/ecs)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from CloudFront (TLS is terminated at CloudFront, not here)"
    from_port   = 80
    to_port     = 80
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
