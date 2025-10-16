locals {
  env = var.tf_env == "main" ? "prod" : "dev"

  # Загружаем конфигурацию ВМ из YAML
  vm_config_raw = yamldecode(file("${path.module}/vms.${local.env}.yaml"))

  # Сопоставление серверов vCenter и alias-провайдеров
  # Здесь мы храним непосредственно ссылки на конфигурации провайдеров (provider references).
  #providers_map = {
  #  "vc-sand-01.roscap.com"    = vsphere.vc-sand-01
  #  "bank-vc-01.roscap.com"    = vsphere.bank-vc-01
  #  "perun.roscap.com"         = vsphere.perun
  #  "vc-b-1001.domrfbank.ru"   = vsphere.vc-b-1001
  #}

  # Преобразуем список ВМ в map
  vm_config = {
    for vm in local.vm_config_raw.vms : vm.name => vm
  }

  disk_letters = ["b", "c", "d", "e", "f", "g"]

  # Сопоставление VRF и их ID (NetBox)
  vrf_map = {
    "BANK-COM" = 37
  }
}

# === Датацентры ===
data "vsphere_datacenter" "dc_sand" {
  for_each = toset(distinct([for vm in local.vm_config : vm.datacenter if vm.vsphere_alias == "vc-sand-01"]))
  name     = each.value
  provider = vsphere.vc-sand-01
}
data "vsphere_datacenter" "dc_bank" {
  for_each = toset(distinct([for vm in local.vm_config : vm.datacenter if vm.vsphere_alias == "bank-vc-01"]))
  name     = each.value
  provider = vsphere.bank-vc-01
}
# === Datastore ===
data "vsphere_datastore" "datastore" {
  for_each      = local.vm_config
  name          = each.value.datastore
  datacenter_id = data.vsphere_datacenter.dc[each.value.datacenter].id
}

# === Кластеры ===
data "vsphere_compute_cluster" "cluster" {
  for_each      = local.vm_config
  name          = each.value.cluster
  datacenter_id = data.vsphere_datacenter.dc[each.value.datacenter].id
}

# === Шаблоны (можно из другого vCenter) ===
# Добавил поиск datacenter, в котором лежит шаблон (в template_server).
# Если в YAML не задано template_datacenter, будет использован datacenter целевой ВМ.
#data "vsphere_datacenter" "template_dc" {
#  for_each = local.vm_config

  # передаём конкретную конфигурацию провайдера через providers = { vsphere = ... }
#   providers = {
#     vsphere = local.providers_map[each.value.vsphere_server]
#   }

#   name     = coalesce(try(each.value.template_datacenter, null), each.value.datacenter)
# #}

data "vsphere_virtual_machine" "template" {
  for_each = local.vm_config

  #  providers = {
  #    vsphere = local.providers_map[each.value.vsphere_server]
  #  }

  name          = each.value.template
  datacenter_id = data.vsphere_datacenter.dc[each.value.datacenter].id
}

# === Сети ===
data "vsphere_network" "network" {
  for_each      = local.vm_config
  name          = each.value.network
  datacenter_id = data.vsphere_datacenter.dc[each.value.datacenter].id
}

# === Storage Policy ===
data "vsphere_storage_policy" "vm_policy" {
  for_each = toset(distinct([for vm in local.vm_config : vm.storage_policy]))
  name     = each.key
}

# === NetBox: Tenants ===
data "netbox_tenant" "tenant" {
  for_each = local.vm_config
  name     = each.value.tenant
}

data "netbox_tenant_group" "group" {
  for_each = local.vm_config
  name     = each.value.tenant_group
}

# === NetBox: Prefix (если IP не задан) ===
data "netbox_prefix" "subnet" {
  for_each = {
    for k, v in local.vm_config :
    k => v if try(v.ip, "") == "" && can(v.subnet)
  }
  prefix = each.value.subnet
}

# === NetBox: Получение свободного IP ===
resource "netbox_available_ip_address" "auto_ip" {
  for_each  = data.netbox_prefix.subnet
  prefix_id = each.value.id
}

# === NetBox: Регистрация IP ===
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

# === Виртуальные машины ===
resource "vsphere_virtual_machine" "vm" {
  provider = vsphere.vc-sand-01
  for_each = { for k,v in local.vm_config : k=>v if try(v.vsphere_server,null) == "vc-sand-01.roscap.com" }

  # Передаём нужную конфигурацию провайдера через providers = { vsphere = ... }
  #  providers = {
  #   vsphere = (
  #     each.value.vsphere_server == "vc-sand-01.roscap.com" ? vsphere.vc-sand-01 :
  #     each.value.vsphere_server == "bank-vc-01.roscap.com" ? vsphere.bank-vc-01 :
  #     each.value.vsphere_server == "perun.roscap.com"      ? vsphere.perun :
  #     each.value.vsphere_server == "vc-b-1001.domrbank.ru" ? vsphere.vc-b-1001 :
  #     vsphere.vc-sand-01 // fallback, если ни один не совпал
  #   )
  # }

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
    ignore_changes  = all
  }

  # === cloud-init ===
  extra_config = {
    "guestinfo.userdata" = base64encode(templatefile("${path.module}/cloud-init.yaml.tpl", {
      extra_disk  = lookup(each.value, "extra_disk", [])
      extend_lvm  = lookup(each.value, "extend_lvm", null)
    }))
    "guestinfo.userdata.encoding" = "base64"
  }

  # === Сеть ===
  network_interface {
    network_id   = data.vsphere_network.network[each.key].id
    adapter_type = data.vsphere_virtual_machine.template[each.key].network_interface_types[0]
  }

  # === Основной диск ===
  disk {
    label             = "disk0"
    size              = each.value.disk
    eagerly_scrub     = false
    thin_provisioned  = data.vsphere_virtual_machine.template[each.key].disks[0].thin_provisioned
    storage_policy_id = data.vsphere_storage_policy.vm_policy[each.value.storage_policy].id
  }

  # === Дополнительные диски ===
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

  # === Клонирование из шаблона ===
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

resource "vsphere_virtual_machine" "vm_bank_vc_01" {
  provider = vsphere.vc-sand-01
  for_each = { for k,v in local.vm_config : k=>v if try(v.vsphere_server,null) == "bank-vc-01.roscap.com" }

  # Передаём нужную конфигурацию провайдера через providers = { vsphere = ... }
  #  providers = {
  #   vsphere = (
  #     each.value.vsphere_server == "vc-sand-01.roscap.com" ? vsphere.vc-sand-01 :
  #     each.value.vsphere_server == "bank-vc-01.roscap.com" ? vsphere.bank-vc-01 :
  #     each.value.vsphere_server == "perun.roscap.com"      ? vsphere.perun :
  #     each.value.vsphere_server == "vc-b-1001.domrbank.ru" ? vsphere.vc-b-1001 :
  #     vsphere.vc-sand-01 // fallback, если ни один не совпал
  #   )
  # }

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
    ignore_changes  = all
  }

  # === cloud-init ===
  extra_config = {
    "guestinfo.userdata" = base64encode(templatefile("${path.module}/cloud-init.yaml.tpl", {
      extra_disk  = lookup(each.value, "extra_disk", [])
      extend_lvm  = lookup(each.value, "extend_lvm", null)
    }))
    "guestinfo.userdata.encoding" = "base64"
  }

  # === Сеть ===
  network_interface {
    network_id   = data.vsphere_network.network[each.key].id
    adapter_type = data.vsphere_virtual_machine.template[each.key].network_interface_types[0]
  }

  # === Основной диск ===
  disk {
    label             = "disk0"
    size              = each.value.disk
    eagerly_scrub     = false
    thin_provisioned  = data.vsphere_virtual_machine.template[each.key].disks[0].thin_provisioned
    storage_policy_id = data.vsphere_storage_policy.vm_policy[each.value.storage_policy].id
  }

  # === Дополнительные диски ===
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

  # === Клонирование из шаблона ===
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
