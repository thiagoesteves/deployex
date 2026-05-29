variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment name (e.g., prod, stage)"
  type        = string
  default     = "prod"
}

variable "app_name" {
  description = "Name of the application"
  type        = string
  default     = "myapp"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b", "us-east-2c"]
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

# Application Configuration
variable "myapp_port" {
  description = "Port exposed by the application"
  type        = number
  default     = 4000
}

variable "deployex_phoenix_port" {
  description = "Port exposed by the DeployEx"
  type        = number
  default     = 5001
}

variable "host_port" {
  description = "Port on the host machine"
  type        = number
  default     = 80
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name of the S3 bucket (will be prefixed with environment and app_name)"
  type        = string
  default     = "assets"
}

variable "s3_enable_versioning" {
  description = "Whether to enable versioning for the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_enable_lifecycle_rules" {
  description = "Whether to enable lifecycle rules for the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_enable_cors" {
  description = "Whether to enable CORS for the S3 bucket"
  type        = bool
  default     = false
}

# Domain Configuration
variable "domain_name" {
  description = "The domain name for the application (e.g., example.com)"
  type        = string
  default     = "myapp.cloud"
}

variable "route53_zone_id" {
  description = "The Route 53 hosted zone ID for the domain"
  type        = string
  default     = "Z019999999999ZB" # You'll need to provide your actual hosted zone ID
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "myapp"
    Environment = "production"
    Terraform   = "true"
  }
}

variable "enable_ssh" {
  description = "Whether to enable SSH access to the EC2 instances"
  type        = bool
  default     = false
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to SSH into the instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS"
  type        = string
  default     = "arn:aws:acm:us-east-2:866666666666:certificate/7ea75d5f-f927-495d-8464-3667ceabe1c1"
}

# NLB Variables
variable "nlb_listener_port" {
  description = "Port on which the NLB will listen for TCP traffic"
  type        = number
  default     = 80
}

variable "enable_deletion_protection" {
  description = "Whether to enable deletion protection for the NLB"
  type        = bool
  default     = false
}

variable "bastion_key_name" {
  description = "Key Pair for SSH (Bastion)"
  type        = string
  default     = "bastion"
}

variable "deployex_version" {
  description = "The default deployex version to install"
  type        = string
  nullable    = false
  default     = "0.9.1"
}