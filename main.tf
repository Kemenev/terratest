locals {
  env = var.tf_env == "main" ? "prod" : "dev"

  # Загружаем конфигурацию ВМ из YAML
  vm_config_raw = yamldecode(file("${path.module}/vms.${local.env}.yaml"))

  # Сопоставление серверов vCenter и alias-провайдеров
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

  # Сопоставление VRF и их ID (NetBox)
  vrf_map = {
    "BANK-COM" = 37
  }
}

# === Датацентры ===
data "vsphere_datacenter" "dc" {
  for_each = toset(distinct([for vm in local.vm_config : vm.datacenter]))
  name     = each.value
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
data "vsphere_virtual_machine" "template" {
  for_each      = local.vm_config
  name          = each.value.template
  datacenter_id = data.vsphere_datacenter.dc[each.value.datacenter].id
  provider      = local.providers_map[each.value.template_server]
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
  for_each = local.vm_config

  provider         = local.providers_map[each.value.vsphere_server]
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
  extra
