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
  type     = string
  nullable = false
}

variable "deployex_version" {
  description = "The default deployex version to install"
  nullable = false
}

variable "machine_type" {
  description = "The Machine instance type"
  type        = string
  nullable    = false
}

variable "region" {
   description = "The GCP region to use"
    type = string
    default = <region> # Example "us-central1"
}

variable "project" {
    type = string
    default = <project_id> # From deployex-gcp-terraform.json (project_id)
}

variable "email" {
    type = string
    default = <client_email> # From deployex-gcp-terraform.json (client_email)
}

variable "privatekeypath" {
    type = string
    default = "~/.ssh/id_rsa"
}

variable "publickeypath" {
    type = string
    default = "~/.ssh/id_rsa.pub"
}
