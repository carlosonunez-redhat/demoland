resource "aws_iam_policy" "allow_access_bootstrap_bucket" {
  name = "allow-full-access-bucket-${local.bootstrap_bucket_name}"
  path = "/"
  description = "Allows full access to the ${local.bootstrap_bucket_name} bucket."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = ["s3:*"]
      Effect = "Allow"
      Resource = "${aws_s3_bucket.bootstrap_bucket.arn}/*"
    }]
  })
}

