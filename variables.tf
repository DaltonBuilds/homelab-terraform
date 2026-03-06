variable "proxmox_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
  default     = ""
}

variable "node_name" {
  description = "Default Proxmox node name - can be overridden by terraform.tfvars"
  type        = string
  default     = "pve"
}

variable "ip_addresses" {
  description = "Map of VM names to IP addresses"
  type        = map(string)
  default     = {}
}

variable "gateway_ip" {
  description = "Gateway IP address for the network"
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "SSH public key for VM and container root access"
  type        = string
}