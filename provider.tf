terraform {
  required_providers {
    vsphere = {
      source = "registry.terraform.io/hashicorp/vsphere"
      version = "2.15.0"
    }
    netbox = {
      source = "e-breuninger/netbox"
      version = "4.2.0"
    }
  }
}
provider "vsphere" {
  user = var.vsphere_user
  password = var.vsphere_password
  vsphere_server = var.vsphere_server
  allow_unverified_ssl = true
}
provider "netbox" {
  server_url = var.netbox_server_url
  api_token  = var.netbox_token
#  server_url = https://dcim.roscap.com/api/
#  api_token  = a550b51cea5d38c88af98e0bebe0c4397a937786
}