variable "environment" {
  description = "Environment name (e.g., prod, staging)"
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

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID for the ALB"
  type        = string
  default     = ""
}

# Domain Configuration
variable "domain_name" {
  description = "The domain name for the application (e.g., example.com)"
  type        = string
}

variable "myapp_port" {
  description = "Port exposed by the container"
  type        = number
}

variable "deployex_phoenix_port" {
  description = "Port exposed by the DeployEx"
  type        = number
  default     = 5001
}

variable "health_check_path" {
  description = "Path for ALB health check"
  type        = string
  default     = "/health"
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for the ALB"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}
