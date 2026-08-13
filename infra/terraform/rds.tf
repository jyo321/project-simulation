resource "aws_db_subnet_group" "main" {
  name       = "northbridge-db-subnets"
  subnet_ids = [for s in aws_subnet.private_data : s.id]
}

resource "aws_db_instance" "postgres" {
  identifier     = "northbridge-postgres"
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

  multi_az                  = true
  backup_retention_period   = 7
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "northbridge-postgres-final"

  tags = { Name = "northbridge-postgres" }
}
