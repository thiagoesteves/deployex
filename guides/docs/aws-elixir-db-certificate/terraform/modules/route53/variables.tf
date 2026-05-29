variable "environment" {
  description = "Environment name (e.g., prod, stage)"
  type        = string
}

variable "app_name" {
  description = "Name of the application"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
}