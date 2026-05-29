#
# Environment values
#

locals {
  myapp_env_vars = [
    {
      name  = "AWS_REGION"
      value = var.aws_region
    },
    {
      name  = "DATABASE_URL"
      value = "postgres://${var.myapp_db_username}:${var.myapp_db_password}@${var.myapp_db_endpoint}/${var.myapp_db_name}"
    },
    {
      name  = "DB_SSL_CERT"
      value = "/etc/ssl/certs/rds-global.pem"
    },
    {
      name  = "ECTO_IPV6"
      value = "false"
    },
    {
      name  = "MAILER_ADAPTER"
      value = "sendgrid"
    },
    {
      name  = "FROM_EMAIL"
      value = "info@myapp.cloud"
    },
    {
      name  = "PHX_HOST"
      value = "myapp.cloud"
    },
    {
      name  = "REPO_POOL_SIZE"
      value = "10"
    },
    {
      name  = "ROUTE53_ZONE_ID"
      value = var.dns_zone_id
    }
  ]

  myapp_env_ports = [
    {
      name  = "PHX_PORT"
      value = 4000
    }
  ]
}
