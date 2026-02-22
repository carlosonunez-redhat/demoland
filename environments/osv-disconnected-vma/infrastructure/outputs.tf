output "connected_bastion_instance_id" {
  value = module.connected-bastion-vm.id
}
output "disconnected_bastion_instance_id" {
  value = module.disconnected-bastion-vm.id
}
output "disconnected_artifactory_instance_id" {
  value = module.disconnected-artifactory-vm.id
}
