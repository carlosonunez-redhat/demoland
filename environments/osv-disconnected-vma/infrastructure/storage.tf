module "bootstrap_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"
  bucket = local.bootstrap_bucket_name
  force_destroy = true
  block_public_acls = false
  block_public_policy = false
  ignore_public_acls = false
  restrict_public_buckets = false
  attach_policy = true
  policy = jsonencode({
    version = "2012-10-17"
    Statement = [
      {
        Sid = "AllowAccessingTestFileFromMyIp"
        Effect = "Allow"
        Principal = "*"
        Action = ["s3:GetObject"]
        Resource = [
          "arn:aws:s3:::${local.bootstrap_bucket_name}/test_file",
          "arn:aws:s3:::${local.bootstrap_bucket_name}/*.ign",
          "arn:aws:s3:::${local.bootstrap_bucket_name}/*.yaml",
        ]
        Condition = {
          IpAddress = {
            "aws:SourceIp" = [
              "${var.ssh_ip}/32"
            ]
          }
        }
      },
      {
        Sid = "AllowAccessToManifestAndIgnitionFilesFromDiscoNetwork"
        Effect = "Allow"
        Principal = "*"
        Action = ["s3:GetObject"]
        Resource = [
          "arn:aws:s3:::${local.bootstrap_bucket_name}/test_file",
          "arn:aws:s3:::${local.bootstrap_bucket_name}/*.ign",
          "arn:aws:s3:::${local.bootstrap_bucket_name}/*.yaml",
        ]
        Condition = {
          IpAddress = {
            "aws:VpcSourceIp" = [
              module.disconnected_network.vpc_cidr_block,
            ]
          }
          StringEquals = {
            "aws:SourceVpc" = module.disconnected_network.vpc_id
          }
        }
      },
      {
        Sid = "AllowAdminFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_iam_session_context.current.arn
        }
        Action = ["s3:*"]
        Resource = [
          "arn:aws:s3:::${local.bootstrap_bucket_name}",
          "arn:aws:s3:::${local.bootstrap_bucket_name}/*"
        ]
      }
    ]
  })
}
