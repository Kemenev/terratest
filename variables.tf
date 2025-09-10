variable "vsphere_user" {
  type = string
  description = "vsphere_username"
}
variable "vsphere_password" {
  type = string
  description = "vsphere_password"
}
variable "vsphere_server" {
  type = string
  description = "vsphere_server"
}

variable "netbox_server_url" {
  type = string
  description = "Netbox API URL"
}
variable "netbox_token" {
  type = string
  description = "Netbox API token"
  sensitive = true
}