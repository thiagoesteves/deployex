output "alb_id" {
  description = "The ID of the ALB"
  value       = aws_lb.main.id
}

output "alb_arn" {
  description = "The ARN of the ALB"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value       = aws_lb.main.dns_name
}

output "myapp_target_group" {
  description = "TLS Myapp target group details"
  value = {
    arn   = aws_lb_target_group.myapp_tg.arn
    ports = var.alb_myapp_listeners
  }
}

output "http_listener_arn" {
  description = "The ARN of the HTTP listener"
  value       = aws_lb_listener.http.arn
}

output "alb_zone_id" {
  description = "The canonical hosted zone ID of the ALB (to be used in a Route53 Alias record)"
  value       = aws_lb.main.zone_id
}

output "deployex_target_group_arn" {
  description = "ARN of the target group for deployex"
  value       = aws_lb_target_group.deployex_tg.arn
}

output "https_listener_arn" {
  description = "The ARN of the HTTPS listener"
  value       = aws_lb_listener.https.arn
}
