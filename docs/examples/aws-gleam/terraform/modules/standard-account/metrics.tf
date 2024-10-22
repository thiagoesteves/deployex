#
#  Logs and metrics
#

resource "aws_cloudwatch_log_group" "ec2_instance_logs" {
  name = "myappname-${var.account_name}-ec2-instance-logs"
}

resource "aws_iam_policy" "ec2_cloudwatch_policy" {
  name = "myappname-${var.account_name}-ec2-cloudwatch-policy"

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