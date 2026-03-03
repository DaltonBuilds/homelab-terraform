terraform {
    required_providers {
        proxmox = {
            source = "bpg/proxmox"
            version = "0.97.1"
        }
    }
}

provider "proxmox" {
    endpoint = "https://192.168.40.50:8006/"
    username = "root@pam"
    password = "123456" # TODO: change to actual password or use a secret / API token
    insecure = true
}