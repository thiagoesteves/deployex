# Create IAM user for programmatic access for Github
resource "aws_iam_user" "github_user" {
  name = "${var.environment}-${var.app_name}-github-user"
  path = "/"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.app_name}-github-user"
    }
  )
}

# Grant Github user read/write/list access to the central S3 distribution
resource "aws_iam_user_policy" "github_s3_distribution_bucket_policy" {
  name = "${var.environment}-${var.app_name}-github-user-policy"
  user = aws_iam_user.github_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "s3:*"
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${var.environment}-${var.app_name}-distribution",
          "arn:aws:s3:::${var.environment}-${var.app_name}-distribution/*"
        ]
      }
    ]
  })
}

# Create access key for the IAM user
resource "aws_iam_access_key" "github_user_key" {
  user = aws_iam_user.github_user.name
}


# Create Secrets
resource "aws_secretsmanager_secret" "github_access_key" {
  name        = "${var.environment}/${var.app_name}/github-access-key"
  description = "Github management access key"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "github_access_key_version" {
  secret_id     = aws_secretsmanager_secret.github_access_key.id
  secret_string = aws_iam_access_key.github_user_key.id
}

resource "aws_secretsmanager_secret" "github_secret_key" {
  name        = "${var.environment}/${var.app_name}/github-secret-key"
  description = "Github management secret key"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "github_secret_key_version" {
  secret_id     = aws_secretsmanager_secret.github_secret_key.id
  secret_string = aws_iam_access_key.github_user_key.secret
}