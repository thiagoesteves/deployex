# IAM Policy for ACM management
resource "aws_iam_policy" "route53_acm_management_policy" {
  name        = "${var.environment}-${var.app_name}-route53-acm-management-policy"
  description = "Policy for managing Route53 resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
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



