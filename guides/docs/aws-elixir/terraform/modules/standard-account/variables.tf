variable "account_name" {
  type     = string
  nullable = false
}

variable "server_dns" {
  type     = string
  nullable = false
}

variable "deployex_dns" {
  type     = string
  nullable = false
}

variable "replicas" {
  type     = number
  nullable = false
}

# ec2 key pair name
variable "aws_key_name" {
  default = "myappname-web-ec2"
}

variable "aws_region" {
  description = "The AWS region to use"
  default     = "sa-east-1"
}

variable "deployex_version" {
  description = "The default deployex version to install"
  nullable = false
}

variable "ec2_instance_type" {
  description = "The EC2 instance type"
  type        = string
  nullable    = false
}