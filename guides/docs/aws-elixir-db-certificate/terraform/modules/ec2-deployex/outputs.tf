output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.ec2_deployex_instance.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.ec2_deployex_instance.arn
}

output "instance_private_ip" {
  description = "Private IP address of the instance"
  value       = aws_instance.ec2_deployex_instance.private_ip
}

output "instance_public_ip" {
  description = "Public IP address of the instance (if applicable)"
  value       = aws_instance.ec2_deployex_instance.public_ip
}

output "instance_private_dns" {
  description = "Private DNS name of the instance"
  value       = aws_instance.ec2_deployex_instance.private_dns
}

output "instance_public_dns" {
  description = "Public DNS name of the instance (if applicable)"
  value       = aws_instance.ec2_deployex_instance.public_dns
}

output "security_group_id" {
  description = "ID of the security group for EC2 instances"
  value       = aws_security_group.ec2_deployex_instances_sg.id
}

output "instance_role_name" {
  description = "Name of the IAM role for EC2 instances"
  value       = aws_iam_role.ec2_deployex_instance_role.name
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile for EC2 instances"
  value       = aws_iam_instance_profile.ec2_deployex_instance_profile.name
}
