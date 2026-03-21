terraform {

  backend "gcs" {
    bucket = "daltonbuilds-homelab-tfstate"
    prefix = "terraform/state"
    impersonate_service_account = "terraform-state@homelab-forge.iam.gserviceaccount.com"
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.97.1"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = true

  ssh {
    agent    = true
    username = "root"
  }
}