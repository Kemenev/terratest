#locals {
#  vm_debug_config = yamldecode(file("${path.module}/vms.yaml"))
#}

#output "vm_ips" {
#    value = [for vm in local.vm_config.vms : vm.ip]
#}

#output "netbox_test_date" {
#  value = local.vm_config.vms
#}
#output "debug_url" {
#  value = var.netbox_server_url
#}

#output "debug_token" {
#  value = var.netbox_token
#  sensitive = true
#}