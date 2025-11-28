#
#  S3 definitions
#

variable "s3_folders" {
  type        = list
  description = "S3 folders to create for distribution"
  default     = ["dist/myappname", "versions/myappname"]
}

resource "aws_s3_bucket" "distribution" {
  bucket = "myappname-${var.account_name}-distribution"

  tags = {
    Name = "Distribution bucket"
  }
}

resource "aws_s3_object" "distribution_directory_structure" {
  count        = "${length(var.s3_folders)}"

  bucket       = "${aws_s3_bucket.distribution.id}"
  acl          = "private"
  key          = "${var.s3_folders[count.index]}/"
  content_type = "application/x-directory"
  source       = "/dev/null"
}

# Grant EC2 instances read access to the central S3 distribution
resource "aws_iam_policy" "s3_distribution_bucket_policy" {
  name = "myappname-${var.account_name}-s3-distribution-bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:s3:::myappname-${var.account_name}-distribution"
      },
      {
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:s3:::myappname-${var.account_name}-distribution/*"
      },
    ]
  })
}


