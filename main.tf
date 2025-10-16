############################################
# Локали и исходные данные
############################################
locals {
  env           = var.tf_env == "main" ? "prod" : "dev"
  vm_config_raw = yamldecode(file("${path.module}/vms.${local.env}.yaml"))

  # Преобразуем список ВМ в map: name => vm
  vm_config = {
    for vm in local.vm_config_raw.vms : vm.name => vm
  }

  disk_letters = ["b", "c", "d", "e", "f", "g"]

  # VRF (NetBox)
  vrf_map = {
    "BANK-COM" = 37
  }
}

############################################
# Datacenter per alias
############################################
data "vsphere_datacenter" "dc_sand" {
  for_each = toset(distinct([
    for vm in local.vm_config : vm.datacenter
    if try(vm.vsphere_alias, "") == "vc-sand-01" || try(vm.vsphere_server, "") == "vc-sand-01.roscap.com"
  ]))
  name     = each.value
  provider = vsphere.vc-sand-01
}

data "vsphere_datacenter" "dc_bank" {
  for_each = toset(distinct([
    for vm in local.vm_config : vm.datacenter
    if try(vm.vsphere_alias, "") == "bank-vc-01" || try(vm.vsphere_server, "") == "bank-vc-01.roscap.com"
  ]))
  name     = each.value
  provider = vsphere.bank-vc-01
}

data "vsphere_datacenter" "dc_perun" {
  for_each = toset(distinct([
    for vm in local.vm_config : vm.datacenter
    if try(vm.vsphere_alias, "") == "perun" || try(vm.vsphere_server, "") == "perun.roscap.com"
  ]))
  name     = each.value
  provider = vsphere.perun
}

data "vsphere_datacenter" "dc_b1001" {
  for_each = toset(distinct([
    for vm in local.vm_config : vm.datacenter
    if try(vm.vsphere_alias, "") == "vc-b-1001" || try(vm.vsphere_server, "") == "vc-b-1001.domrfbank.ru"
  ]))
  name     = each.value
  provider = vsphere.vc-b-1001
}

# Единая прокси‑мапа Datacenter: local.dc["<dc>"].id
locals {
  dc = merge(
    { for k, v in data.vsphere_datacenter.dc_sand  : k => v },
    { for k, v in data.vsphere_datacenter.dc_bank  : k => v },
    { for k, v in data.vsphere_datacenter.dc_perun : k => v },
    { for k, v in data.vsphere_datacenter.dc_b1001 : k => v }
  )
}

############################################
# Datastore per alias -> local.ds[each.key].id
############################################
data "vsphere_datastore" "ds_sand" {
  for_each      = { for k, v in local.vm_config : k => v if try(v.vsphere_alias, "") == "vc-sand-01" || try(v.vsphere_server, "") == "vc-sand-01.roscap.com" }
  name          = each.value.datastore
  datacenter_id = local.dc[each.value.datacenter].id
  provider      = vsphere.vc-sand-01
}

data "vsphere_datastore" "ds_bank" {
  for_each      = { for k, v in local.vm_config : k => v if try(v.vsphere_alias, "") == "bank-vc-01" || try(v.vsphere_server, "") == "bank-vc-01.roscap.com" }
  name          = each.value.datastore
  datacenter_id = local.dc[each.value.datacenter].id
  provider      = vsphere.bank-vc-01
}

data "vsphere_datastore" "ds_perun" {
  for_each      = { for k, v in local.vm_config : k => v if try(v.vsphere_alias, "") == "perun" || try(v.vsphere_server, "") == "perun.roscap.com" }
  name          = each.value.datastore
  datacenter_id = local.dc[each.value.datacenter].id
  provider      = vsphere.perun
}

data "vsphere_datastore" "ds_b1001" {
  for_each      = { for k, v in local.vm_config : k => v if try(v.vsphere_alias, "") == "vc-b-1001" || try(v.vsphere_server, "") == "vc-b-1001.domrfbank.ru" }
  name          = each.value.datastore
  datacenter_id = local.dc[each.value.datacenter].id
  provider      = vsphere.vc-b-1001
}

locals {
  ds = merge(
    { for k, v in data.vsphere_datastore.ds_sand  : k => v },
    { for k, v in data.vsphere_datastore.ds_bank  : k => v },
    { for k, v in data.vsphere_datastore.ds_perun : k => v },
    { for k, v in data.vsphere_datastore.ds_b1001 : k => v }
  )
}

############################################
# Cluster per alias -> local.cluster[each.key].id
############################################
data "vsphere_compute_cluster" "cl_sand" {
  for_each      = { for k, v in local.vm_config : k => v if try(v.vsphere_alias, "") == "vc-sand-01" || try(v.vsphere_server, "") == "vc-sand-01.roscap.com" }
  name          = each.value.cluster
  datacenter_id = local.dc[each.value.datacenter].id
  provider      = vsphere.vc-sand-01
}

data "vsphere_compute_cluster" "cl_bank" {
  for_each      = { for k, v in local.vm_config : k => v if try(v.vsphere_alias, "") == "bank-vc-01" || try(v.vsphere_server, "") == "bank-vc-01.roscap.com" }
  name          = each.value.cluster
  datacenter_id = local.dc[each.value.datacenter].id
  provider      = vsphere.bank-vc-01
}

data "vsphere_compute_cluster" "cl_perun" {
  for_each      = { for k, v in local.vm_config : k => v if try(v.vsphere_alias, "") == "perun" || try(v.vsphere_server, "") == "perun.roscap.com" }
  name          = each.value.cluster
  datacenter_id = local.dc[each.value.datacenter].id
  provider      = vsphere.perun
}

data "vsphere_compute_cluster" "cl_b1001" {
  for_each      = { for k, v in local.vm_config : k => v if try(v.vsphere_alias, "") == "vc-b-1001" || try(v.vsphere_server, "") == "vc-b-1001.domrfbank.ru" }
  name          = each.value.cluster
  datacenter_id = local.dc[each.value.datacenter].id
  provider      = vsphere.vc-b-1001
}

locals {
  cluster = merge(
    { for k, v in data.vsphere_compute_cluster.cl_sand  : k => v },
    { for k, v in data.vsphere_compute_cluster.cl_bank  : k => v },
    { for k, v in data.vsphere_compute_cluster.cl_perun : k => v },
    { for k, v in data.vsphere_compute_cluster.cl_b1001 : k => v }
  )
}

############################################
# Network per alias -> local.net[each.key].id
############################################
data "vsphere_network" "net_sand" {
  for_each      = { for k, v in local.vm_config : k => v if try(v.vsphere_alias, "") == "vc-sand-01" || try(v.vsphere_server, "") == "vc-sand-01.roscap.com" }
  name          = each.value.network
  datacenter_id = local.dc[each.value.datacenter].id
  provider      = vsphere.vc-sand-01
}

data "vsphere_network" "net_bank" {
  for_each      = { for k, v in local.vm_config : k => v if try(v.vsphere_alias, "") == "bank-vc-01" || try(v.vsphere_server, "") == "bank-vc-01.roscap.com" }
  name          = each.value.network
  datacenter_id = local.dc[each.value.datacenter].id
  provider      = vsphere.bank-vc-01
}

data "vsphere_network" "net_perun" {
  for_each      = { for k, v in local.vm_config : k => v if try(v.vsphere_alias, "") == "perun" || try(v.vsphere_server, "") == "perun.roscap.com" }
  name          = each.value.network
  datacenter_id = local.dc[each.value.datacenter].id
  provider      = vsphere.perun
}

data "vsphere_network" "net_b1001" {
  for_each      = { for k, v in local.vm_config : k => v if try(v.vsphere_alias, "") == "vc-b-1001" || try(v.vsphere_server, "") == "vc-b-1001.domrfbank.ru" }
  name          = each.value.network
  datacenter_id = local.dc[each.value.datacenter].id
  provider      = vsphere.vc-b-1001
}

locals {
  net = merge(
    { for k, v in data.vsphere_network.net_sand  : k => v },
    { for k, v in data.vsphere_network.net_bank  : k => v },
    { for k, v in data.vsphere_network.net_perun : k => v },
    { for k, v in data.vsphere_network.net_b1001 : k => v }
  )
}

############################################
# Template per template_server -> local.tpl[each.key]
############################################
data "vsphere_virtual_machine" "tpl_sand" {
  for_each = {
    for k, v in local.vm_config :
    k => v if try(v.template_server, "") == "vc-sand-01.roscap.com"
  }
  name          = each.value.template
  datacenter_id = local.dc[coalesce(try(each.value.template_datacenter, null), each.value.datacenter)].id
  provider      = vsphere.vc-sand-01
}

data "vsphere_virtual_machine" "tpl_bank" {
  for_each = {
    for k, v in local.vm_config :
    k => v if try(v.template_server, "") == "bank-vc-01.roscap.com"
  }
  name          = each.value.template
  datacenter_id = local.dc[coalesce(try(each.value.template_datacenter, null), each.value.datacenter)].id
  provider      = vsphere.bank-vc-01
}

data "vsphere_virtual_machine" "tpl_perun" {
  for_each = {
    for k, v in local.vm_config :
    k => v if try(v.template_server, "") == "perun.roscap.com"
  }
  name          = each.value.template
  datacenter_id = local.dc[coalesce(try(each.value.template_datacenter, null), each.value.datacenter)].id
  provider      = vsphere.perun
}

data "vsphere_virtual_machine" "tpl_b1001" {
  for_each = {
    for k, v in local.vm_config :
    k => v if try(v.template_server, "") == "vc-b-1001.domrfbank.ru"
  }
  name          = each.value.template
  datacenter_id = local.dc[coalesce(try(each.value.template_datacenter, null), each.value.datacenter)].id
  provider      = vsphere.vc-b-1001
}

locals {
  tpl = merge(
    { for k, v in data.vsphere_virtual_machine.tpl_sand  : k => v },
    { for k, v in data.vsphere_virtual_machine.tpl_bank  : k => v },
    { for k, v in data.vsphere_virtual_machine.tpl_perun : k => v },
    { for k, v in data.vsphere_virtual_machine.tpl_b1001 : k => v }
  )
}

############################################
# Storage Policy (строго по имени, без игнора)
############################################
data "vsphere_storage_policy" "pol_sand" {
  for_each = toset(distinct([
    for vm in local.vm_config : vm.storage_policy
    if try(vm.vsphere_alias, "") == "vc-sand-01" || try(vm.vsphere_server, "") == "vc-sand-01.roscap.com"
  ]))
  name     = each.key
  provider = vsphere.vc-sand-01
}

data "vsphere_storage_policy" "pol_bank" {
  for_each = toset(distinct([
    for vm in local.vm_config : vm.storage_policy
    if try(vm.vsphere_alias, "") == "bank-vc-01" || try(vm.vsphere_server, "") == "bank-vc-01.roscap.com"
  ]))
  name     = each.key
  provider = vsphere.bank-vc-01
}

data "vsphere_storage_policy" "pol_perun" {
  for_each = toset(distinct([
    for vm in local.vm_config : vm.storage_policy
    if try(vm.vsphere_alias, "") == "perun" || try(vm.vsphere_server, "") == "perun.roscap.com"
  ]))
  name     = each.key
  provider = vsphere.perun
}

data "vsphere_storage_policy" "pol_b1001" {
  for_each = toset(distinct([
    for vm in local.vm_config : vm.storage_policy
    if try(vm.vsphere_alias, "") == "vc-b-1001" || try(vm.vsphere_server, "") == "vc-b-1001.domrfbank.ru"
  ]))
  name     = each.key
  provider = vsphere.vc-b-1001
}

locals {
  pol = merge(
    { for k, v in data.vsphere_storage_policy.pol_sand  : k => v },
    { for k, v in data.vsphere_storage_policy.pol_bank  : k => v },
    { for k, v in data.vsphere_storage_policy.pol_perun : k => v },
    { for k, v in data.vsphere_storage_policy.pol_b1001 : k => v }
  )
}

############################################
# NetBox
############################################
data "netbox_tenant" "tenant" {
  for_each = local.vm_config
  name     = each.value.tenant
}

data "netbox_tenant_group" "group" {
  for_each = local.vm_config
  name     = each.value.tenant_group
}

data "netbox_prefix" "subnet" {
  for_each = { for k, v in local.vm_config : k => v if try(v.ip, "") == "" && can(v.subnet) }
  prefix   = each.value.subnet
}

resource "netbox_available_ip_address" "auto_ip" {
  for_each  = data.netbox_prefix.subnet
  prefix_id = each.value.id
}

resource "netbox_ip_address" "ip" {
  for_each   = local.vm_config
  ip_address = coalesce(
    try(each.value.ip, ""),
    try(netbox_available_ip_address.auto_ip[each.key].ip_address, null)
  )
  status      = "reserved"
  dns_name    = each.key
  description = each.value.notes
  tenant_id   = data.netbox_tenant.tenant[each.key].id
  vrf_id      = lookup(local.vrf_map, each.value.vrf, null)

  lifecycle {
    prevent_destroy = true
  }
}

############################################
# Виртуальные машины — vc-sand-01
############################################
resource "vsphere_virtual_machine" "vm_sand" {
  provider = vsphere.vc-sand-01
  for_each = { for k, v in local.vm_config : k => v if try(v.vsphere_alias, "") == "vc-sand-01" || try(v.vsphere_server, "") == "vc-sand-01.roscap.com" }

  name             = each.key
  resource_pool_id = local.cluster[each.key].resource_pool_id
  datastore_id     = local.ds[each.key].id

  num_cpus   = each.value.cpu
  memory     = each.value.ram
  guest_id   = local.tpl[each.key].guest_id
  scsi_type  = local.tpl[each.key].scsi_type
  annotation = each.value.notes
  custom_attributes = lookup(each.value, "custom_attributes", {})

  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }

  extra_config = {
    "guestinfo.userdata"          = base64encode(templatefile("${path.module}/cloud-init.yaml.tpl", {
      extra_disk = lookup(each.value, "extra_disk", [])
      extend_lvm = lookup(each.value, "extend_lvm", null)
    }))
    "guestinfo.userdata.encoding" = "base64"
  }

  network_interface {
    network_id   = local.net[each.key].id
    adapter_type = local.tpl[each.key].network_interface_types[0]
  }

  disk {
    label             = "disk0"
    size              = each.value.disk
    eagerly_scrub     = false
    thin_provisioned  = local.tpl[each.key].disks[0].thin_provisioned
    storage_policy_id = local.pol[each.value.storage_policy].id
  }

  dynamic "disk" {
    for_each = { for idx, d in lookup(each.value, "extra_disk", []) : idx => d }
    content {
      label            = "disk${disk.key + 1}"
      size             = disk.value.size
      unit_number      = disk.key + 1
      thin_provisioned = true
      eagerly_scrub    = false
    }
  }

  clone {
    template_uuid = local.tpl[each.key].id

    customize {
      linux_options {
        host_name = each.key
        domain    = each.value.domain
      }

      network_interface {
        ipv4_address = split("/", coalesce(try(each.value.ip, ""), try(netbox_available_ip_address.auto_ip[each.key].ip_address, null)))[0]
        ipv4_netmask = tonumber(split("/", coalesce(try(each.value.ip, ""), try(netbox_available_ip_address.auto_ip[each.key].ip_address, null)))[1])
      }

      ipv4_gateway    = each.value.gateway
      dns_server_list = each.value.dns
      dns_suffix_list = [each.value.env]
    }
  }
}

############################################
# Виртуальные машины — bank-vc-01
############################################
resource "vsphere_virtual_machine" "vm_bank" {
  provider = vsphere.bank-vc-01
  for_each = { for k, v in local.vm_config : k => v if try(v.vsphere_alias, "") == "bank-vc-01" || try(v.vsphere_server, "") == "bank-vc-01.roscap.com" }

  name             = each.key
  resource_pool_id = local.cluster[each.key].resource_pool_id
  datastore_id     = local.ds[each.key].id

  num_cpus   = each.value.cpu
  memory     = each.value.ram
  guest_id   = local.tpl[each.key].guest_id
  scsi_type  = local.tpl[each.key].scsi_type
  annotation = each.value.notes
  custom_attributes = lookup(each.value, "custom_attributes", {})

  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }

  extra_config = {
    "guestinfo.userdata"          = base64encode(templatefile("${path.module}/cloud-init.yaml.tpl", {
      extra_disk = lookup(each.value, "extra_disk", [])
      extend_lvm = lookup(each.value, "extend_lvm", null)
    }))
    "guestinfo.userdata.encoding" = "base64"
  }

  network_interface {
    network_id   = local.net[each.key].id
    adapter_type = local.tpl[each.key].network_interface_types[0]
  }

  disk {
    label             = "disk0"
    size              = each.value.disk
    eagerly_scrub     = false
    thin_provisioned  = local.tpl[each.key].disks[0].thin_provisioned
    storage_policy_id = local.pol[each.value.storage_policy].id
  }

  dynamic "disk" {
    for_each = { for idx, d in lookup(each.value, "extra_disk", []) : idx => d }
    content {
      label            = "disk${disk.key + 1}"
      size             = disk.value.size
      unit_number      = disk.key + 1
      thin_provisioned = true
      eagerly_scrub    = false
    }
  }

  clone {
    template_uuid = local.tpl[each.key].id

    customize {
      linux_options {
        host_name = each.key
        domain    = each.value.domain
      }

      network_interface {
        ipv4_address = split("/", coalesce(try(each.value.ip, ""), try(netbox_available_ip_address.auto_ip[each.key].ip_address, null)))[0]
        ipv4_netmask = tonumber(split("/", coalesce(try(each.value.ip, ""), try(netbox_available_ip_address.auto_ip[each.key].ip_address, null)))[1])
      }

      ipv4_gateway    = each.value.gateway
      dns_server_list = each.value.dns
      dns_suffix_list = [each.value.env]
    }
  }
}
