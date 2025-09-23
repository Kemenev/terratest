locals {
  vm_config_raw = yamldecode(file("${path.module}/vms.yaml"))

  # Преобразуем список ВМ в map: "vm-name" => { параметры }
  vm_config = {
    for vm in local.vm_config_raw.vms : vm.name => vm
  }
  disk_letters = ["b", "c", "d", "e", "f", "g"]
  vrf_map = {
    "BANK-COM" = 37
    # можно добавить остальные VRF и их ID из NetBox
  }
}

# Получаем список всех датацентров
data "vsphere_datacenter" "dc" {
  for_each = toset(distinct([for vm in local.vm_config : vm.datacenter]))
  name = each.value
}


# Datastores
data "vsphere_datastore" "datastore" {
  for_each = local.vm_config
  name          = each.value.datastore
  datacenter_id = data.vsphere_datacenter.dc[each.value.datacenter].id
}

# Кластеры
data "vsphere_compute_cluster" "cluster" {
  for_each = local.vm_config
  name          = each.value.cluster
  datacenter_id = data.vsphere_datacenter.dc[each.value.datacenter].id
}

# Templates
data "vsphere_virtual_machine" "template" {
  for_each = local.vm_config
  name          = each.value.template
  datacenter_id = data.vsphere_datacenter.dc[each.value.datacenter].id
}

# Сеть
data "vsphere_network" "network" {
  for_each = local.vm_config
  name          = each.value.network
  datacenter_id = data.vsphere_datacenter.dc[each.value.datacenter].id
}

# Storage policy
data "vsphere_storage_policy" "vm_policy" {
  for_each = toset(distinct([
    for vm in local.vm_config : vm.storage_policy
  ]))
  name = each.key
}

# NetBox: Tenant
data "netbox_tenant" "tenant" {
  for_each = local.vm_config
  name     = each.value.tenant
}

data "netbox_tenant_group" "group" {
  for_each = local.vm_config
  name     = each.value.tenant_group
}

# NetBox IP address
resource "netbox_ip_address" "ip" {
  for_each      = local.vm_config
  ip_address      = each.value.ip
  status          = "active"
  dns_name        = each.key
  description     = each.value.notes
  tenant_id       = data.netbox_tenant.tenant[each.key].id
#  tenant_group_id = data.netbox_tenant_group.group[each.key].id
  vrf_id          = lookup(local.vrf_map, each.value.vrf, null)
}

# Виртуальная машина

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
  custom_attributes = lookup(each.value, "custom_attributes", {})
  lifecycle {
    prevent_destroy = true
  }

  extra_config = {
    "guestinfo.userdata" = base64encode(templatefile("${path.module}/cloud-init.yaml.tpl", {
      extra_disk = lookup(each.value, "extra_disk", [])
      extend_lvm         = lookup(each.value, "extend_lvm", null)
    }))
    "guestinfo.userdata.encoding" = "base64"
  }

  network_interface {
    network_id   = data.vsphere_network.network[each.key].id
    adapter_type = data.vsphere_virtual_machine.template[each.key].network_interface_types[0]
  }

  disk {
    label             = "disk0"
    size              = each.value.disk
    eagerly_scrub     = false
    thin_provisioned  = data.vsphere_virtual_machine.template[each.key].disks[0].thin_provisioned
    storage_policy_id = data.vsphere_storage_policy.vm_policy[each.value.storage_policy].id
  }

  dynamic "disk" {
    for_each = { for idx, disk in lookup(each.value, "extra_disk", []) : idx => disk }
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
        ipv4_address = split("/", each.value.ip)[0]
        ipv4_netmask = tonumber(split("/", each.value.ip)[1])
      }
      ipv4_gateway    = each.value.gateway
      dns_server_list = each.value.dns
      dns_suffix_list = [each.value.env]
    }
  }
}
