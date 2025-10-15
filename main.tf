locals {
  env           = var.tf_env == "main" ? "prod" : "dev"
  vm_config_raw = yamldecode(file("${path.module}/vms.${local.env}.yaml"))

  # Карта "FQDN vCenter" -> "alias провайдера"
  providers_map = {
    "vc-sand-01.roscap.com"  = "vc-sand-01"
    "bank-vc-01.roscap.com"  = "bank-vc-01"
    "perun.roscap.com"       = "perun"
    "vc-b-1001.domrfbank.ru" = "vc-b-1001"
  }

  # Преобразуем список ВМ в map
  vm_config = {
    for vm in local.vm_config_raw.vms : vm.name => vm
  }

  # Прочие  локальные переменные
  disk_letters = ["b", "c", "d", "e", "f", "g"]

  vrf_map = {
    "BANK-COM" = 37
  }
}

#########
# Data  #
#########

# Datacenter: по ВМ, чтобы искать в правильном vCenter
data "vsphere_datacenter" "dc" {
  for_each = local.vm_config
  provider = vsphere[lookup(local.providers_map, coalesce(try(each.value.vsphere_server, null), var.vsphere_server), "vc-sand-01")]
  name     = each.value.datacenter
}

# Datastore
data "vsphere_datastore" "datastore" {
  for_each      = local.vm_config
  provider      = vsphere[lookup(local.providers_map, coalesce(try(each.value.vsphere_server, null), var.vsphere_server), "vc-sand-01")]
  name          = each.value.datastore
  datacenter_id = data.vsphere_datacenter.dc[each.key].id
}

# Cluster
data "vsphere_compute_cluster" "cluster" {
  for_each      = local.vm_config
  provider      = vsphere[lookup(local.providers_map, coalesce(try(each.value.vsphere_server, null), var.vsphere_server), "vc-sand-01")]
  name          = each.value.cluster
  datacenter_id = data.vsphere_datacenter.dc[each.key].id
}

# Network
data "vsphere_network" "network" {
  for_each      = local.vm_config
  provider      = vsphere[lookup(local.providers_map, coalesce(try(each.value.vsphere_server, null), var.vsphere_server), "vc-sand-01")]
  name          = each.value.network
  datacenter_id = data.vsphere_datacenter.dc[each.key].id
}

# Storage Policy
data "vsphere_storage_policy" "vm_policy" {
  for_each = local.vm_config
  provider = vsphere[lookup(local.providers_map, coalesce(try(each.value.vsphere_server, null), var.vsphere_server), "vc-sand-01")]
  name     = each.value.storage_policy
}

# Datacenter с шаблоном: можно указать другой vCenter для шаблона
data "vsphere_datacenter" "template_dc" {
  for_each = local.vm_config
  # Если template_server не задан, используем vsphere_server ВМ, иначе var.vsphere_server
  local_template_server = coalesce(try(each.value.template_server, null), coalesce(try(each.value.vsphere_server, null), var.vsphere_server))

  provider = vsphere[lookup(local.providers_map, local_template_server, "vc-sand-01")]
  name     = coalesce(try(each.value.template_datacenter, null), each.value.datacenter)
}

# Template VM
data "vsphere_virtual_machine" "template" {
  for_each      = local.vm_config
  local_template_server = coalesce(try(each.value.template_server, null), coalesce(try(each.value.vsphere_server, null), var.vsphere_server))

  provider      = vsphere[lookup(local.providers_map, local_template_server, "vc-sand-01")]
  name          = each.value.template
  datacenter_id = data.vsphere_datacenter.template_dc[each.key].id
}

#########################
# Ресурс VM   #
#########################

resource "vsphere_virtual_machine" "vm" {
  for_each = local.vm_config

  provider = vsphere[lookup(local.providers_map, coalesce(try(each.value.vsphere_server, null), var.vsphere_server), "vc-sand-01")]

  name             = each.key
  resource_pool_id = data.vsphere_compute_cluster.cluster[each.key].resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore[each.key].id

  num_cpus   = each.value.cpu
  memory     = each.value.ram
  annotation = each.value.notes

  guest_id  = data.vsphere_virtual_machine.template[each.key].guest_id
  scsi_type = data.vsphere_virtual_machine.template[each.key].scsi_type

  # Ваши custom_attributes
  custom_attributes = lookup(each.value, "custom_attributes", {})

  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }

  network_interface {
    network_id   = data.vsphere_network.network[each.key].id
    adapter_type = data.vsphere_virtual_machine.template[each.key].network_interface_types[0]
  }

  # Системный диск
  disk {
    label             = "disk0"
    size              = each.value.disk
    eagerly_scrub     = false
    thin_provisioned  = data.vsphere_virtual_machine.template[each.key].disks[0].thin_provisioned
    storage_policy_id = data.vsphere_storage_policy.vm_policy[each.key].id
  }

  # Дополнительные диски из extra_disk
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
    template_uuid = data.vsphere_virtual_machine.template[each.key].id
    customize {
      linux_options {
        host_name = each.key
        domain    = each.value.domain
      }
      network_interface {
        # здесь оставьте вашу текущую логику IP (статический/из NetBox), если была
      }
      ipv4_gateway    = each.value.gateway
      dns_server_list = each.value.dns
      dns_suffix_list = [each.value.env]
    }
  }
}
