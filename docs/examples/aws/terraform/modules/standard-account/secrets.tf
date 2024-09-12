# ATTENTION: The values are expected to be set manually by the DASHBOARD
#
# If it is not running on development, remove the recovery_window_in_days = 0
# from the secrets
#
locals {
  secret_tag = {
    ManagedManually = true
  }
}

resource "aws_secretsmanager_secret" "deployex_secrets" {
  name                    = "deployex-myappname-${var.account_name}-secrets"
  description             = "All Deployex Secrets"
  recovery_window_in_days = 0
  tags = local.secret_tag
}

resource "aws_secretsmanager_secret" "myappname_secrets" {
  name                    = "myappname-${var.account_name}-secrets"
  description             = "All Myappname Secrets"
  recovery_window_in_days = 0
  tags = local.secret_tag
}

resource "aws_secretsmanager_secret" "myappname_otp_tls_ca" {
  name                    = "myappname-${var.account_name}-otp-tls-ca"
  description             = "TLS ca certificate for OTP distribution"
  recovery_window_in_days = 0
  tags = local.secret_tag
}

resource "aws_secretsmanager_secret" "myappname_otp_tls_key" {
  name                    = "myappname-${var.account_name}-otp-tls-key"
  description             = "TLS key certificate for OTP distribution"
  recovery_window_in_days = 0
  tags = local.secret_tag
}

resource "aws_secretsmanager_secret" "myappname_otp_tls_crt" {
  name                    = "myappname-${var.account_name}-otp-tls-crt"
  description             = "TLS key certificate for OTP distribution"
  recovery_window_in_days = 0
  tags = local.secret_tag
}

# Create an IAM policy to grant access to Secrets Manager
resource "aws_iam_policy" "myappname_secrets_manager_policy" {
  name        = "myappname-${var.account_name}-secrets-manager-access-policy"
  description = "Policy for EC2 to access Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
        ],
        Effect = "Allow",
        Resource = [
          aws_secretsmanager_secret.myappname_secrets.arn,
          aws_secretsmanager_secret.myappname_otp_tls_ca.arn,
          aws_secretsmanager_secret.myappname_otp_tls_key.arn,
          aws_secretsmanager_secret.myappname_otp_tls_crt.arn,
          aws_secretsmanager_secret.deployex_secrets.arn,
        ],
      },
    ],
  })
}
