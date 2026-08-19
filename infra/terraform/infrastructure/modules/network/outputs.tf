output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "private_app_subnet_ids" {
  value = [for s in aws_subnet.private_app : s.id]
}

output "private_data_subnet_ids" {
  value = [for s in aws_subnet.private_data : s.id]
}

output "security_group_alb_id" {
  value = aws_security_group.alb.id
}

output "security_group_ecs_app_id" {
  value = aws_security_group.ecs_app.id
}

output "security_group_ecs_worker_id" {
  value = aws_security_group.ecs_worker.id
}

output "security_group_rds_id" {
  value = aws_security_group.rds.id
}
