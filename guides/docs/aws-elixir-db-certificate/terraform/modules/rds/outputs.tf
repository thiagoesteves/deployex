output "db_instance_id" {
  description = "The ID of the RDS instance"
  value       = aws_db_instance.main.id
}

output "db_instance_address" {
  description = "The address of the RDS instance"
  value       = aws_db_instance.main.address
}

output "db_instance_endpoint" {
  description = "The connection endpoint of the RDS instance"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_name" {
  description = "The database name"
  value       = aws_db_instance.main.db_name
}

output "db_instance_username" {
  description = "The master username for the database"
  value       = aws_db_instance.main.username
}

output "db_instance_port" {
  description = "The database port"
  value       = aws_db_instance.main.port
}

output "db_subnet_group_id" {
  description = "The ID of the database subnet group"
  value       = aws_db_subnet_group.main.id
}

output "db_security_group_id" {
  description = "The ID of the database security group"
  value       = aws_security_group.db.id
}

output "db_parameter_group_id" {
  description = "The ID of the database parameter group"
  value       = aws_db_parameter_group.main.id
}

output "db_password_secret_arn" {
  description = "The ARN of the Secrets Manager secret storing the database password"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "db_password" {
  description = "The DB password"
  value       = random_password.db_password.result
  sensitive   = true
}