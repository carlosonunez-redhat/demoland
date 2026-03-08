locals {
  ipxe_user_data_base = <<-EOF
  #!ipxe
  set base http://${local.bootstrap_bucket_name}.s3.${data.aws_region.current.region}.amazonaws.com
  kernel $${base}/kernel \
    ip=auto \
    BOOT_IMAGE=(hd0,gpt3)/boot/ostree/rhcos-51c77ffa2c1c0968abd5b430b98d71f3df0ec76d1bd99613c484f15bfac5a4ad/vmlinuz-5.14.0-570.74.1.el9_6.x86_64 \
    rw \
    ignition.firstboot \
    ostree=/ostree/boot.1/rhcos/51c77ffa2c1c0968abd5b430b98d71f3df0ec76d1bd99613c484f15bfac5a4ad/0 \
    ignition.platform.id=aws \
    init=/bin/bash \
    initrd=main \
    coreos.inst.install_dev=/dev/nvme0n1 \
    coreos.inst.ignition_url=$${base}/openshift_install/REPLACE_ME.ign \
    ignition.config.url=$${base}/openshift_install/REPLACE_ME.ign \
    console=tty0 \
    console=ttyS0,115200n8 \
    rd.multipath=default
  initrd --name main $${base}/initramfs.img
  boot
  EOF
}

module "disconnected-bastion-vm" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "bastion-disconnected"
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.vm
  availability_zone = local.default_availability_zone
  associate_public_ip_address = false
  ami = data.aws_ami.fedora_x86.id
  key_name = module.ec2_key.key_pair_name
  subnet_id = local.provisioning_subnet_disconnected
  vpc_security_group_ids = [ module.disconnected-sg-bastion.security_group_id ]
  create_security_group = false
  root_block_device = {
    type       = "gp3"
    size       = 500
  }
}

module "disconnected-artifactory-vm" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "artifactory-disconnected"
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.vm
  ami = data.aws_ami.fedora_x86.id
  key_name = module.ec2_key.key_pair_name
  subnet_id = local.provisioning_subnet_disconnected
  vpc_security_group_ids = [
    module.disconnected-sg-artifactory.security_group_id,
  ]
  create_security_group = false
  root_block_device = {
    type       = "gp3"
    size       = 500
  }
}

module "disconnected-ocp-bootstrap-node" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "ocp-cp-${count.index}"
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.vm
  ami = data.aws_ami.ipxe.id
  key_name = module.ec2_key.key_pair_name
  subnet_id = local.provisioning_subnet_disconnected
  vpc_security_group_ids = [
    module.disconnected-sg-ocp-control-plane.security_group_id,
    module.disconnected-sg-ocp-worker.security_group_id,
  ]
  create_security_group = false
  root_block_device = {
    type       = "gp3"
    size       = 100
  }
  metadata_options = {
    http_tokens = "optional"
  }
  user_data = replace(local.ipxe_user_data_base, "REPLACE_ME", "bootstrap")
  timeouts = {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

module "disconnected-ocp-cp-nodes-bm" {
  count = fileexists(var.bare_metal_creation_sentinel_file) ? 3 : 0
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "ocp-cp-${count.index}"
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.bare_metal.control_plane
  ami = data.aws_ami.ipxe.id
  key_name = module.ec2_key.key_pair_name
  subnet_id = local.provisioning_subnet_disconnected
  vpc_security_group_ids = [ module.disconnected-sg-ocp-control-plane.security_group_id ]
  create_security_group = false
  root_block_device = {
    type       = "gp3"
    size       = 100
  }
  metadata_options = {
    http_tokens = "optional"
  }
  user_data = replace(local.ipxe_user_data_base, "REPLACE_ME", "master")
  timeouts = {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

module "disconnected-ocp-worker-nodes-bm" {
  count = fileexists(var.bare_metal_creation_sentinel_file) ? 3 : 0
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "ocp-worker-${count.index}"
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.bare_metal.workers
  ami = data.aws_ami.ipxe.id
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.disconnected_network.private_subnets[count.index]
  vpc_security_group_ids = [ module.disconnected-sg-ocp-worker.security_group_id ]
  create_security_group = false
  root_block_device = {
    type       = "gp3"
    size       = 100
  }
  metadata_options = {
    http_tokens = "optional"
  }
  user_data = replace(local.ipxe_user_data_base, "REPLACE_ME", "worker")
  timeouts = {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

# module "disconnected-esx-host-bm" {
#   count = fileexists(var.bare_metal_creation_sentinel_file) ? 3 : 0
#   source = "terraform-aws-modules/ec2-instance/aws"
#   name = "ocp-cp"
#   ami = data.aws_ami.ipxe.id
#   instance_type = local.options.cloud_config.aws.compute.instance_sizes.bare_metal
#   key_name = module.ec2_key.key_pair_name
# subnet_id = module.disconnected_network.private_subnets[count.index]
#   vpc_security_group_ids = [ module.disconnected-sg-ocp-to-artifactory.security_group_id ]
#   create_security_group = false
#   root_block_device = {
#     type       = "gp3"
#     size       = 100
#   }
# }
