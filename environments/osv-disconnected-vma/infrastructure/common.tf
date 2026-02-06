data "tls_public_key" "ec2_key" {
  private_key_pem = file("/secrets/ssh-key")
}

module "ec2_key" {
  source = "terraform-aws-modules/key-pair/aws"
  key_name = "key"
  public_key = data.tls_public_key.ec2_key.public_key_openssh
}
