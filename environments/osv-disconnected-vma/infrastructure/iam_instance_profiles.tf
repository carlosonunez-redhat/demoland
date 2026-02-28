resource "aws_iam_instance_profile" "allow_access_bootstrap_bucket" {
  name = "access-bucket-instance-role-${local.bootstrap_bucket_name}"
  role = aws_iam_role.bootstrap_bucket_instance_role.name
}
