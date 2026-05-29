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

variable "subnet_id" {
  description = "Subnet ID where the instance will be created"
  type        = string
}

variable "custom_port" {
  description = "Custom port to allow inbound traffic (0 to disable)"
  type        = number
  default     = 0
}

variable "create_iam_role" {
  description = "Whether to create an IAM role for the instance"
  type        = bool
  default     = true
}

variable "root_volume_type" {
  description = "Type of root volume"
  type        = string
  default     = "gp3"
}

variable "root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
  default     = 20
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "bastion_security_group_id" {
  description = "Security group ID of the bastion host for SSH access"
  type        = string
  default     = ""
}

variable "enable_ssh" {
  description = "Whether to enable SSH access to the instances"
  type        = bool
  default     = false
}

variable "enable_http" {
  description = "Enable HTTP access (port 80)"
  type        = bool
  default     = false
}

variable "enable_https" {
  description = "Enable HTTPS access (port 443)"
  type        = bool
  default     = false
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to SSH into the instances"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}

variable "dns_zone_id" {
  description = "Route53 hosted zone ID for DNS record creation"
  type        = string
}

variable "key_name" {
  description = "EC2 Key Pair"
  type        = string
}

variable "associate_public_ip" {
  description = "Whether to associate a public IP address"
  type        = bool
  default     = false
}

variable "myapp_replicas" {
  description = "Number of Application replicas"
  type        = number
  nullable    = false
  default     = 1
}

variable "deployex_version" {
  description = "The default deployex version to install"
  type        = string
  nullable    = false
}

variable "dns_record_name" {
  description = "Deployex DNS"
  type        = string
  nullable    = false
  default     = "deployex.myapp.cloud"
}

variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
}

variable "myapp_db_name" {
  description = "Application DB name"
  type        = string
}

variable "myapp_db_username" {
  description = "Application DB username"
  type        = string
}

variable "myapp_db_endpoint" {
  description = "Application DB endpoint"
  type        = string
}

variable "myapp_db_password" {
  description = "Application DB Password"
  type        = string
}

variable "ses_access_key" {
  description = "SES access key"
  type        = string
}

variable "ses_secret_key" {
  description = "SES secret key"
  type        = string
}

variable "route53_access_key" {
  description = "String of the Secrets Manager secret containing Route53 management access key"
  type        = string
  sensitive   = true
}

variable "route53_secret_key" {
  description = "String of the Secrets Manager secret containing Route53 management secret key"
  type        = string
  sensitive   = true
}

variable "route53_role_arn" {
  description = "ARN of the Secrets Manager secret containing Route53 management role ARN"
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS"
  type        = string
}

variable "myapp_cert_domain" {
  description = "Domain"
  type        = string
  nullable    = false
  default     = "*.calori.com.br"
}

variable "myapp_cert_email" {
  description = "Acme contact email"
  type        = string
  nullable    = false
  default     = "info@example.cloud"
}

variable "myapp_cert_acme_zone" {
  description = "DNS zone"
  type        = string
  nullable    = false
  default     = "12345678"
}
