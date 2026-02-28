resource "aws_s3_bucket" "bootstrap_bucket" {
  bucket = "ignition-bootstrap-${random_string.bootstrap_bucket.result}"
  force_destroy = true
}
