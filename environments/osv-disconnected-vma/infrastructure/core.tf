terraform {
  backend "s3" {}
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.31.0"
    }
  }
}
