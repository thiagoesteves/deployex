resource "aws_lb" "main" {
  name               = "${var.environment}-${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.app_name}-alb"
    }
  )
}

variable "alb_myapp_listeners" {
  type        = list(string)
  description = "ALB Myapp listeners port numbers"
  default     = [4000, 4001]
}

resource "aws_lb_target_group" "myapp_tg" {
  name        = "${var.environment}-${var.app_name}-tg"
  port        = var.myapp_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  # Set connection draining time to 30 seconds
  deregistration_delay = 30

  health_check {
    enabled             = true
    interval            = 10
    path                = var.health_check_path
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    protocol            = "HTTP"
    matcher             = "200-299"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.app_name}-tg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.myapp_tg.arn
  }
}

resource "aws_lb_target_group" "deployex_tg" {
  name        = "${var.environment}-${var.app_name}-deployex-tg"
  port        = var.deployex_phoenix_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  # Set connection draining time to 30 seconds
  deregistration_delay = 30

  health_check {
    enabled             = true
    interval            = 30
    path                = var.health_check_path
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    protocol            = "HTTP"
    matcher             = "200-299"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.app_name}-deployex-tg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Host-based routing rule for deployex
resource "aws_lb_listener_rule" "deployex_routing" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.deployex_tg.arn
  }

  condition {
    host_header {
      values = ["deployex.${var.domain_name}"]
    }
  }
}