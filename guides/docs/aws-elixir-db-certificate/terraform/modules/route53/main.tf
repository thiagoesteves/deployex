# IAM Role for Route53 management
resource "aws_iam_role" "route53_management_role" {
  name = "${var.environment}-${var.app_name}-route53-management-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.route53_user.arn
        }
      },
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.app_name}-route53-management-role"
    }
  )
}

# IAM Policy for Route53/ACM management
resource "aws_iam_policy" "route53_acm_management_policy" {
  name        = "${var.environment}-${var.app_name}-route53-acm-management-policy"
  description = "Policy for managing Route53 resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          # Route53 actions
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:GetHostedZone",
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          # ACM actions
          "acm:ImportCertificate",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "acm:DeleteCertificate",
          "acm:AddTagsToCertificate",
          "acm:ListTagsForCertificate",
          "acm:GetCertificate"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })

  tags = var.tags
}

# Attach policy to the role
resource "aws_iam_role_policy_attachment" "route53_acm_policy_attachment" {
  role       = aws_iam_role.route53_management_role.name
  policy_arn = aws_iam_policy.route53_acm_management_policy.arn
}

# Create IAM user for programmatic access
resource "aws_iam_user" "route53_user" {
  name = "${var.environment}-${var.app_name}-route53-user"
  path = "/"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.app_name}-route53-user"
    }
  )
}

# Allow the IAM user to assume the Route53 management role
resource "aws_iam_user_policy" "route53_user_assume_role_policy" {
  name = "assume-route53-management-role"
  user = aws_iam_user.route53_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "sts:AssumeRole"
        Effect   = "Allow"
        Resource = aws_iam_role.route53_management_role.arn
      }
    ]
  })
}

# Create access key for the IAM user
resource "aws_iam_access_key" "route53_user_key" {
  user = aws_iam_user.route53_user.name
}

# Store access key in AWS Secrets Manager
resource "aws_secretsmanager_secret" "route53_access_key" {
  name        = "${var.environment}/${var.app_name}/route53-access-key"
  description = "Route53 management access key"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "route53_access_key_version" {
  secret_id     = aws_secretsmanager_secret.route53_access_key.id
  secret_string = aws_iam_access_key.route53_user_key.id
}

# Store secret key in AWS Secrets Manager
resource "aws_secretsmanager_secret" "route53_secret_key" {
  name        = "${var.environment}/${var.app_name}/route53-secret-key"
  description = "Route53 management secret key"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "route53_secret_key_version" {
  secret_id     = aws_secretsmanager_secret.route53_secret_key.id
  secret_string = aws_iam_access_key.route53_user_key.secret
}
