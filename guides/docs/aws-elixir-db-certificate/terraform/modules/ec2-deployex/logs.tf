#
#  Logs and metrics
#

resource "aws_cloudwatch_log_group" "ec2_deployex_instance_logs" {
  name = "/ec2/${var.environment}-${var.app_name}-deployex"

  retention_in_days = 30

  tags = merge(
    var.tags,
    {
      Name = "/ec2/${var.environment}-${var.app_name}-deployex"
    }
  )
}

resource "aws_iam_policy" "ec2_deployex_cloudwatch_policy" {
  name = "${var.environment}-${var.app_name}-ec2-cloudwatch-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:Create*",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}