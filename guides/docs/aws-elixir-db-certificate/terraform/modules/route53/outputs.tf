output "route53_access_key" {
  description = "Secret containing Route53 management access key"
  value       = aws_secretsmanager_secret_version.route53_access_key_version.secret_string
  sensitive   = true
}

output "route53_secret_key" {
  description = "Secret containing Route53 management secret key"
  value       = aws_secretsmanager_secret_version.route53_secret_key_version.secret_string
  sensitive   = true
}

output "route53_role_arn" {
  description = "ARN of the Secrets Manager secret for Route53"
  value       = aws_iam_role.route53_management_role.arn
}