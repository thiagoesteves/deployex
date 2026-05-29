variable "environment" {
  description = "Environment name (e.g., prod, stage)"
  type        = string
}

variable "app_name" {
  description = "Name of the application"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "database_subnet_ids" {
  description = "List of subnet IDs for the database subnet group"
  type        = list(string)
}

variable "bastion_security_group_id" {
  description = "Security group ID for the bastion host (optional)"
  type        = string
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs that need database access (e.g., Debian instance)"
  type        = list(string)
  default     = []
}

variable "postgres_version" {
  description = "Version of PostgreSQL to use"
  type        = string
  default     = "17.5"
}

variable "db_instance_class" {
  description = "The instance type for the RDS instance"
  type        = string
  default     = "db.t4g.small"
}

variable "allocated_storage" {
  description = "The amount of storage to allocate to the RDS instance (in GB)"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "The maximum amount of storage to allocate to the RDS instance (in GB)"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "The name of the database to create"
  type        = string
  default     = "myapp_prod"
}

variable "db_username" {
  description = "The username for the database"
  type        = string
  default     = "myapp_b4677G6Zd9"
}

variable "backup_retention_period" {
  description = "The number of days to retain backups"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot when the database is deleted"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection for the database"
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Whether to enable Performance Insights"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}
