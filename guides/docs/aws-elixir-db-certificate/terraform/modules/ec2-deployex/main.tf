data "aws_ami" "ec2_deployex_ami_id" {
  most_recent = true
  owners      = ["136693071363"] # Debian official

  filter {
    name   = "name"
    values = ["debian-13-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_iam_policy_document" "ec2_deployex_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ec2_deployex_instance_role" {
  name               = "${var.environment}-${var.app_name}-ec2-deployex-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_deployex_assume_role.json
  tags               = var.tags
}

resource "aws_iam_instance_profile" "ec2_deployex_instance_profile" {
  name = "${var.environment}-${var.app_name}-ec2-deployex-instance-profile"
  role = aws_iam_role.ec2_deployex_instance_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_deployex_instance_role_attachment" {
  count      = var.create_iam_role ? 1 : 0
  role       = aws_iam_role.ec2_deployex_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "attach_s3" {
  role       = aws_iam_role.ec2_deployex_instance_role.name
  policy_arn = aws_iam_policy.s3_distribution_bucket_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_secrets" {
  role       = aws_iam_role.ec2_deployex_instance_role.name
  policy_arn = aws_iam_policy.deployex_secrets_manager_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_cloudwatch" {
  role       = aws_iam_role.ec2_deployex_instance_role.name
  policy_arn = aws_iam_policy.ec2_deployex_cloudwatch_policy.arn
}

# Security group for the EC2 instances
resource "aws_security_group" "ec2_deployex_instances_sg" {
  name        = "${var.environment}-${var.app_name}-ec2-deployex-instance-sg"
  description = "Security group for EC2 deployex + intances"
  vpc_id      = var.vpc_id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH access from bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = var.bastion_security_group_id != "" ? [var.bastion_security_group_id] : []
    description     = "Allow SSH from Bastion host"
  }

  # Allow SSH access from specified CIDR blocks if enabled
  dynamic "ingress" {
    for_each = var.enable_ssh ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_allowed_cidr_blocks
      description = "Allow SSH from specified CIDR blocks"
    }
  }

  # Allow HTTP traffic if enabled
  dynamic "ingress" {
    for_each = var.enable_http ? [1] : []
    content {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow HTTP traffic"
    }
  }

  # Allow HTTPS traffic if enabled
  dynamic "ingress" {
    for_each = var.enable_https ? [1] : []
    content {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow HTTPS traffic"
    }
  }

  # Allow custom port if specified
  dynamic "ingress" {
    for_each = var.custom_port != 0 ? [1] : []
    content {
      from_port   = var.custom_port
      to_port     = var.custom_port
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow custom port ${var.custom_port}"
    }
  }

  # For all app ports, the range will be base + replicas

  # Port 4000 (Custom application port)
  ingress {
    from_port   = 4000
    to_port     = 4001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow NLB traffic on port 5001 (Deployex UI)"
  }

  # Allow NLB traffic on port 5001
  ingress {
    from_port   = 5001
    to_port     = 5001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow NLB traffic on port 5001 (DeployEx UI)"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.app_name}-ec2-deployex-instance-sg"
    }
  )
}

data "cloudinit_config" "server_config" {
  gzip          = true
  base64_encode = true
  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-config.tpl", {
      deployex_hostname = "${var.dns_record_name}"
      deployex_version  = "${var.deployex_version}"
      log_group_name    = aws_cloudwatch_log_group.ec2_deployex_instance_logs.name
      environment       = "${var.environment}"
      app_name          = "${var.app_name}"
      aws_region        = "${var.aws_region}"
      myapp_replicas    = var.myapp_replicas
      app_hostname      = "${var.dns_record_name}"
      myapp_env_vars    = local.myapp_env_vars
      myapp_env_ports   = local.myapp_env_ports
      myapp_secrets     = local.myapp_secrets
      myapp_cert_domain    = var.myapp_cert_domain
      myapp_cert_email     = var.myapp_cert_email
      myapp_cert_acme_zone = var.myapp_cert_acme_zone
      myapp_cert_arn       = var.certificate_arn
    })
  }
}

resource "aws_instance" "ec2_deployex_instance" {
  ami           = data.aws_ami.ec2_deployex_ami_id.id
  instance_type = var.instance_type
  key_name      = var.key_name

  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.ec2_deployex_instances_sg.id]
  associate_public_ip_address = var.associate_public_ip

  iam_instance_profile = var.create_iam_role ? aws_iam_instance_profile.ec2_deployex_instance_profile.name : null

  user_data                   = data.cloudinit_config.server_config.rendered
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "${var.environment}-${var.app_name}-ec2-deployex-instance"
  }

  lifecycle {
    prevent_destroy = false
    ignore_changes  = [user_data]
  }
}

# Elastic IP for static public IP address
resource "aws_eip" "deployex_ec2_instance" {
  count    = var.associate_public_ip ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.ec2_deployex_instance.id

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.app_name}-ec2-deployex-eip"
    }
  )

  depends_on = [aws_instance.ec2_deployex_instance]
}
