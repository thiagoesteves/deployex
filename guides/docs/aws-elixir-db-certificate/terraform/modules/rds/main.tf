resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-${var.app_name}-db-subnet-group"
  subnet_ids = var.database_subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.app_name}-db-subnet-group"
    }
  )
}

resource "aws_security_group" "db" {
  name        = "${var.environment}-${var.app_name}-db-sg"
  description = "Security group for the RDS database"
  vpc_id      = var.vpc_id

  # Allow SSH from Bastion host (if bastion security group ID is provided)
  dynamic "ingress" {
    for_each = var.bastion_security_group_id != "" ? [1] : []
    content {
      from_port       = 22
      to_port         = 22
      protocol        = "tcp"
      security_groups = [var.bastion_security_group_id]
      description     = "Allow SSH from Bastion host"
    }
  }

  # Allow PostgreSQL tunneling from Bastion SG (if bastion security group ID is provided)
  dynamic "ingress" {
    for_each = var.bastion_security_group_id != "" ? [1] : []
    content {
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [var.bastion_security_group_id]
      description     = "Allow PostgreSQL (tunnel) from Bastion host"
    }
  }

  # Allow PostgreSQL access from additional security groups (e.g., Debian instance)
  dynamic "ingress" {
    for_each = var.additional_security_group_ids
    content {
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
      description     = "Allow PostgreSQL access from additional security group"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.app_name}-db-sg"
    }
  )
}

resource "aws_db_parameter_group" "main" {
  name   = "${var.environment}-${var.app_name}-pg-params"
  family = "postgres17"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.app_name}-pg-params"
    }
  )
}

# NOTE: Using URL-safe special characters only. Avoid @, :, /, ?, %, & 
# which break Elixir connection URL parsing (user:pass@host:port/db format)
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!*-_=+"
}

resource "aws_secretsmanager_secret" "db_password" {
  name        = "${var.environment}/${var.app_name}/db/password"
  description = "Database password for ${var.environment} ${var.app_name}"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

resource "aws_db_instance" "main" {
  identifier            = "${var.environment}-${var.app_name}-db"
  engine                = "postgres"
  engine_version        = var.postgres_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result
  port     = 5432

  vpc_security_group_ids = [aws_security_group.db.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.main.name

  maintenance_window      = "Mon:00:00-Mon:03:00"
  backup_window           = "03:00-06:00"
  backup_retention_period = var.backup_retention_period

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = "${var.environment}-${var.app_name}-db-final-snapshot"

  deletion_protection = var.deletion_protection

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  performance_insights_enabled = var.performance_insights_enabled

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.app_name}-db"
    }
  )
}
