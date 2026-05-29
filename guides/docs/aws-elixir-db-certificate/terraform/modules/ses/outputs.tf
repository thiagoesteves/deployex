output "ses_access_key" {
  description = "SES access key"
  value       = aws_secretsmanager_secret_version.ses_access_key_version.secret_string
  sensitive   = true
}

output "ses_secret_key" {
  description = "SES secret key"
  value       = aws_secretsmanager_secret_version.ses_secret_key_version.secret_string
  sensitive   = true
}