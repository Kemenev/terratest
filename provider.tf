terraform {
  required_providers {
    vsphere = {
      source = "registry.terraform.io/hashicorp/vsphere"
      version = "2.15.0"
    }
    netbox = {
      source = "e-breuninger/netbox"
      version = "5.0.0"
    }
  }
}
provider "vsphere" {
  alias = "bank-vc-01"
  user = var.vsphere_user
  password = var.vsphere_password
  vsphere_server = "bank-vc-01.roscap.com"
  allow_unverified_ssl = true
}
provider "vsphere" {
  alias = "vc-sand-01"
  user = var.vsphere_user
  password = var.vsphere_password
  vsphere_server = "vc-sand-01.roscap.com"
  allow_unverified_ssl = true
}
provider "vsphere" {
  alias = "perun"
  user = var.vsphere_user
  password = var.vsphere_password
  vsphere_server = "perun.roscap.com"
  allow_unverified_ssl = true
}
provider "vsphere" {
  alias = "vc-b-1001"
  user = var.vsphere_user
  password = var.vsphere_password
  vsphere_server = "vc-b-1001.domrfbank.ru"
  allow_unverified_ssl = true
}
provider "netbox" {
  server_url = var.netbox_server_url
  api_token  = var.netbox_token
#  server_url = https://dcim.roscap.com/api/
#  api_token  = a550b51cea5d38c88af98e0bebe0c4397a937786
}
