resource "aws_db_subnet_group" "main" {
  name       = "northbridge-db-subnets-${local.environment}"
  subnet_ids = [for s in aws_subnet.private_data : s.id]
}

# Suffixes the final snapshot's identifier so a second destroy/recreate cycle in the same
# workspace doesn't collide with the previous cycle's snapshot (AWS rejects a duplicate
# final_snapshot_identifier). Only regenerates when the RDS instance itself is destroyed
# and recreated from scratch, not on every apply.
resource "random_id" "rds_snapshot_suffix" {
  byte_length = 4
}

resource "aws_db_instance" "postgres" {
  identifier     = "northbridge-postgres-${local.environment}"
  engine         = "postgres"
  engine_version = "16.4"

  instance_class    = var.db_instance_class
  allocated_storage = 50
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az                  = var.db_multi_az
  backup_retention_period   = 7
  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "northbridge-postgres-final-${local.environment}-${random_id.rds_snapshot_suffix.hex}"

  tags = { Name = "northbridge-postgres-${local.environment}" }
}
