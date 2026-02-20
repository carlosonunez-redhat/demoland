module "ec2_key" {
  source = "terraform-aws-modules/key-pair/aws"
  key_name = "key"
  public_key = data.tls_public_key.ec2_key.public_key_openssh
}

data "aws_ami" "ipxe" {
  most_recent = true
  filter {
    name = "name"
    values = [ "iPXE*" ]
  }
  filter {
    name = "architecture"
    values = [ "x86_64" ]
  }
  filter {
    name = "virtualization-type"
    values = [ "hvm" ]
  }
  filter {
    name = "owner-id"
    values = [ "833372943033" ] # source: https://ipxe.org/howto/ec2
  }
}

data "aws_ami" "fedora_arm" {
  most_recent = true
  filter {
    name = "name"
    values = [ "Fedora-Cloud-Base*-43-*" ]
  }
  filter {
    name = "owner-id"
    values = [ "125523088429" ] # source: https://wiki.centos.org/Cloud(2f)AWS.html
  }
  filter {
    name = "architecture"
    values = [ "arm64" ]
  }
  filter {
    name = "virtualization-type"
    values = [ "hvm" ]
  }
}

data "aws_ami" "fedora_x86" {
  most_recent = true
  filter {
    name = "name"
    values = [ "Fedora-Cloud-Base*-43-*" ]
  }
  filter {
    name = "owner-id"
    values = [ "125523088429" ] # source: https://wiki.centos.org/Cloud(2f)AWS.html
  }
  filter {
    name = "architecture"
    values = [ "x86_64" ]
  }
  filter {
    name = "virtualization-type"
    values = [ "hvm" ]
  }
}
