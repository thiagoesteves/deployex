data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "ec2_security" {
  name        = "myappname-${var.account_name}-ec2-security-group"
  description = "Allow SSH traffic from everywhere"
  vpc_id      = aws_vpc.custom_vpc.id
}

resource "aws_security_group_rule" "allow_ingress_ssh" {
  security_group_id = "${aws_security_group.ec2_security.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_ingress_http" {
  security_group_id = "${aws_security_group.ec2_security.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_ingress_https" {
  security_group_id = "${aws_security_group.ec2_security.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_egress_all" {
  security_group_id = "${aws_security_group.ec2_security.id}"
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ec2_iam_role" {
  name               = "myappname-${var.account_name}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "attach_s3" {
  role       = aws_iam_role.ec2_iam_role.name
  policy_arn = aws_iam_policy.s3_distribution_bucket_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_secrets" {
  role       = aws_iam_role.ec2_iam_role.name
  policy_arn = aws_iam_policy.cochito_secrets_manager_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_cloudwatch" {
  role       = aws_iam_role.ec2_iam_role.name
  policy_arn = aws_iam_policy.ec2_cloudwatch_policy.arn
}

resource "aws_iam_instance_profile" "myappname_node" {
  name = "myappname-${var.account_name}-ec2-profile"
  role = aws_iam_role.ec2_iam_role.name
}

data "cloudinit_config" "server_config" {
  gzip          = true
  base64_encode = true
  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-config.tpl", {
      hostname = "${var.server_dns}"
      deployex_hostname = "${var.deployex_dns}"
      deployex_version = "${var.deployex_version}"
      log_group_name = aws_cloudwatch_log_group.ec2_instance_logs.name
      account_name = "${var.account_name}"
      aws_region = "${var.aws_region}"
      replicas = "${var.replicas}"
    })
  }
}

resource "aws_instance" "ec2_myappname_instance" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "${var.ec2_instance_type}"
  key_name                    = "${var.aws_key_name}"
  vpc_security_group_ids      = [aws_security_group.ec2_security.id]
  subnet_id                   = aws_subnet.public_subnet.id
  iam_instance_profile        = aws_iam_instance_profile.myappname_node.name
  associate_public_ip_address = true
  user_data                   = data.cloudinit_config.server_config.rendered
  user_data_replace_on_change = true

  tags = {
    Name = "myappname-${var.account_name}-instance"
  }
  lifecycle {
    create_before_destroy = true
  }
}
