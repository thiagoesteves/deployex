# 
# Secrets - ATTENTION: The values are expected to be set manually by the DASHBOARD
#

# Deployex Secrets
resource "aws_secretsmanager_secret" "deployex_secrets" {
  name        = "${var.environment}/${var.app_name}/deployex/secrets"
  description = "All Deployex Secrets"
}

resource "aws_secretsmanager_secret" "deployex_otp_tls_ca" {
  name        = "${var.environment}/${var.app_name}/deployex/otp-tls-ca"
  description = "TLS ca certificate for OTP distribution"
}

resource "aws_secretsmanager_secret" "deployex_otp_tls_key" {
  name        = "${var.environment}/${var.app_name}/deployex/otp-tls-key"
  description = "TLS key certificate for OTP distribution"
}

resource "aws_secretsmanager_secret" "deployex_otp_tls_crt" {
  name        = "${var.environment}/${var.app_name}/deployex/otp-tls-crt"
  description = "TLS key certificate for OTP distribution"
}

resource "aws_secretsmanager_secret" "myapp_sendgrid_api_key" {
  name        = "${var.environment}/${var.app_name}/sendgrid-api-key"
  description = "Sendgrid api key for sending emails"
}

# Create an IAM policy to grant access to Secrets Manager
resource "aws_iam_policy" "deployex_secrets_manager_policy" {
  name        = "${var.environment}-${var.app_name}-deployex-secrets-manager-access-policy"
  description = "Policy for EC2 deployex to access Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
        ],
        Effect = "Allow",
        Resource = [
          aws_secretsmanager_secret.deployex_otp_tls_ca.arn,
          aws_secretsmanager_secret.deployex_otp_tls_key.arn,
          aws_secretsmanager_secret.deployex_otp_tls_crt.arn,
          aws_secretsmanager_secret.deployex_secrets.arn,
          aws_secretsmanager_secret.myapp_sendgrid_api_key.arn,
        ],
      },
    ],
  })
}

# Application Secrets
resource "aws_secretsmanager_secret" "secret_key_base" {
  name        = "${var.environment}/${var.app_name}/secret-key-base"
  description = "Secret Key Base for Application Phoenix"
}

data "aws_secretsmanager_secret_version" "secret_key_base_version" {
  secret_id = aws_secretsmanager_secret.secret_key_base.arn
}

data "aws_secretsmanager_secret_version" "sendgrid_api_key_version" {
  secret_id = aws_secretsmanager_secret.myapp_sendgrid_api_key.arn
}

resource "aws_secretsmanager_secret" "erlang_cookie" {
  name        = "${var.environment}/${var.app_name}/erlang-cookie"
  description = "Erlang cookie used for OTP distribution"
}

data "aws_secretsmanager_secret_version" "erlang_cookie_version" {
  secret_id = aws_secretsmanager_secret.erlang_cookie.arn
}

locals {
  # NOTE: This secrets need to be removed from here and fetched
  #       by config_provider
  myapp_secrets = [
    {
      name  = "AWS_ACCESS_KEY_ID"
      value = var.route53_access_key
    },
    {
      name  = "AWS_SECRET_ACCESS_KEY"
      value = var.route53_secret_key
    },
    {
      name  = "ROUTE53_ROLE_ARN"
      value = var.route53_role_arn
    },
    {
      name  = "SECRET_KEY_BASE"
      value = data.aws_secretsmanager_secret_version.secret_key_base_version.secret_string
    },
    {
      name  = "SENDGRID_API_KEY"
      value = data.aws_secretsmanager_secret_version.sendgrid_api_key_version.secret_string
    },
    {
      name  = "SES_ACCESS_KEY"
      value = var.ses_access_key
    },
    {
      name  = "SES_SECRET_KEY"
      value = var.ses_secret_key
    },
    {
      name  = "RELEASE_COOKIE"
      value = data.aws_secretsmanager_secret_version.erlang_cookie_version.secret_string
    }
  ]
}
