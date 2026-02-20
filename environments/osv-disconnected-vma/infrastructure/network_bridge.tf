locals {
  bastion_bridge_ip = cidrhost(module.disconnected_network.private_subnets_cidr_blocks[0], 252)
}

resource "aws_network_interface" "bastion-bridge" {
  subnet_id = module.disconnected_network.private_subnets[0]
  private_ips = [ local.bastion_bridge_ip ]
  attachment {
    instance = module.connected-bastion-vm.id
    device_index = 1
  }
}
