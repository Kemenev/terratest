locals {
  env = var.tf_env == "main" ? "prod" : "dev"
  vm_config_raw = yamldecode(file("${path.module}/vms.${local.env}.yaml"))

  providers_map = {
    "vc-sand-01.roscap.com"    = vsphere.vc-sand-01
    "bank-vc-01.roscap.com"    = vsphere.bank-vc-01
    "perun.roscap.com"         = vsphere.perun
    "vc-b-1001.domrfbank.ru"   = vsphere.vc-b-1001
  }

  # Преобразуем список ВМ в map
  vm_config = {
    for vm in local.vm_config_raw.vms : vm.name => vm
  }

  disk_letters = ["b", "c", "d", "e", "f", "g"]

  vrf_map = {
    "BANK-COM" = 37
  }
}

# ======== vSphere data sources ========

data "vsphere_datacenter" "dc" {
  for_each = toset(distinct([for vm in local.vm_config : vm.datacenter]))
  name     = each.value
}

data "vsphere_datastore" "datastore" {
  for_each      = local.vm_config
  name          = each.value.datastore
  datacenter_id = data.vsphere_datacenter.dc[each.value.datacenter].id
}

data "vsphere_compute_cluster" "cluster" {
  for_each      = local.vm_config
  name          = each.value.cluster
  datacenter_id = data.vsphere_datacenter.dc[each.value.datacenter].id
}

data "vsphere_virtual_machine" "template" {
  for_each      = local.vm_config
  name          = each.value.template
  datacenter_id = data.vsphere_datacenter.dc[each.value.datacenter].id
}

data "vsphere_network" "network" {
  for_each      = local.vm_config
  name          = each.value.network
  datacenter_id = data.vsphere_datacenter.dc[each.value.datacenter].id
}

data "vsphere_storage_policy" "vm_policy" {
  for_each = toset(distinct([for vm in local.vm_config : vm.storage_policy]))
  name     = each.key
}

# ======== NetBox integration ========

data "netbox_tenant" "tenant" {
  for_each = local.vm_config
  name     = each.value.tenant
}

data "netbox_tenant_group" "group" {
  for_each = local.vm_config
  name     = each.value.tenant_group
}

# Подсеть берём только если ip пуст
data "netbox_prefix" "subnet" {
  for_each = {
    for k, v in local.vm_config :
    k => v if try(v.ip, "") == "" && can(v.subnet)
  }
  prefix = each.value.subnet
}

resource "netbox_available_ip_address" "auto_ip" {
  for_each  = data.netbox_prefix.subnet
  prefix_id = each.value.id
}

resource "netbox_ip_address" "ip" {
  for_each      = local.vm_config
  ip_address    = coalesce(
    try(each.value.ip, ""),
    try(netbox_available_ip_address.auto_ip[each.key].ip_address, null)
  )
  status        = "reserved"
  dns_name      = each.key
  description   = each.value.notes
  tenant_id     = data.netbox_tenant.tenant[each.key].id
  vrf_id        = lookup(local.vrf_map, each.value.vrf, null)

  lifecycle {
    prevent_destroy = true
  }
}

# ======== VM Creation ========

resource "vsphere_virtual_machine" "vm" {
  for_each         = local.vm_config
  name             = each.key
  resource_pool_id = data.vsphere_compute_cluster.cluster[each.key].resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore[each.key].id
  num_cpus         = each.value.cpu
  memory           = each.value.ram
  guest_id         = data.vsphere_virtual_machine.template[each.key].guest_id
  scsi_type        = data.vsphere_virtual_machine.template[each.key].scsi_type
  annotation       = each.value.notes
  provider         = local.providers_map[each.value.vsphere_server]

  custom_attributes = lookup(each.value, "custom_attributes", {})

  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }

  extra_config = {
    "guestinfo.userdata" = base64encode(templatefile("${path.module}/cloud-init.yaml.tpl", {
      extend_lvm  = lookup(each.value, "extend_lvm", [])
      extra_disk  = lookup(each.value, "extra_disk", [])
    }))
    "guestinfo.userdata.encoding" = "base64"
  }

  network_interface {
    network_id   = data.vsphere_network.network[each.key].id
    adapter_type = data.vsphere_virtual_machine.template[each.key].network_interface_types[0]
  }

  # Основной диск
  disk {
    label             = "disk0"
    size              = each.value.disk
    eagerly_scrub     = false
    thin_provisioned  = data.vsphere_virtual_machine.template[each.key].disks[0].thin_provisioned
    storage_policy_id = data.vsphere_storage_policy.vm_policy[each.value.storage_policy].id
  }

  # Дополнительные диски
  dynamic "disk" {
    for_each = lookup(each.value, "extra_disk", [])
    content {
      label            = "disk${disk.key + 1}"
      size             = disk.value.size
      unit_number      = disk.key + 1
      thin_provisioned = true
      eagerly_scrub    = false
    }
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template[each.key].id
    customize {
      linux_options {
        host_name = each.key
        domain    = each.value.domain
      }

      network_interface {
        ipv4_address = split("/", coalesce(
          try(each.value.ip, ""),
          try(netbox_available_ip_address.auto_ip[each.key].ip_address, null)
        ))[0]
        ipv4_netmask = tonumber(split("/", coalesce(
          try(each.value.ip, ""),
          try(netbox_available_ip_address.auto_ip[each.key].ip_address, null)
        ))[1])
      }

      ipv4_gateway    = each.value.gateway
      dns_server_list = each.value.dns
      dns_suffix_list = [each.value.env]
    }
  }
}
