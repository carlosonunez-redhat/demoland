resource "aws_iam_role" "bootstrap_bucket_instance_role" {
  name = "access-bucket-instance-role-${local.bootstrap_bucket_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Type = "Service"
        Identifiers = ["ec2.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}


resource "aws_iam_role_policy_attachment" "bootstrap_bucket_instance_role" {
  role = aws_iam_role.bootstrap_bucket_instance_role.name
  policy_arn = aws_iam_policy.allow_access_bootstrap_bucket.arn
}

