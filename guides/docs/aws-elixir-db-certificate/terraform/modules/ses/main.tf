# Create IAM user for programmatic access to SES
resource "aws_iam_user" "ses_user" {
  name = "${var.environment}-${var.app_name}-ses-user"
  path = "/"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.app_name}-ses-user"
    }
  )
}

# Create direct policy for SendRawEmail to the IAM user
resource "aws_iam_user_policy" "ses_user_direct_policy" {
  name = "ses-send-raw-email-policy"
  user = aws_iam_user.ses_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ses:SendRawEmail",
          "ses:GetSendQuota"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Create access key for the IAM user
resource "aws_iam_access_key" "ses_user_key" {
  user = aws_iam_user.ses_user.name
}


# Create Secrets
resource "aws_secretsmanager_secret" "ses_access_key" {
  name        = "${var.environment}/${var.app_name}/ses-access-key"
  description = "SES management access key"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "ses_access_key_version" {
  secret_id     = aws_secretsmanager_secret.ses_access_key.id
  secret_string = aws_iam_access_key.ses_user_key.id
}

resource "aws_secretsmanager_secret" "ses_secret_key" {
  name        = "${var.environment}/${var.app_name}/ses-secret-key"
  description = "SES management secret key"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "ses_secret_key_version" {
  secret_id     = aws_secretsmanager_secret.ses_secret_key.id
  secret_string = aws_iam_access_key.ses_user_key.secret
}