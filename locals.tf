locals {
  nodes = {
    "gimli" = {
      id        = 100
      ip        = var.ip_addresses["gimli"]
      snippet   = templatefile("${path.module}/cloud-init/gimli.yaml", { ssh_public_keys = var.ssh_public_keys })
      cores     = 4
      memory    = 8192
      disk_size = 50
      tags      = ["node", "homelab", "k3s-worker", "cluster-workloads"]
    }
    "nfs-server" = {
      id        = 101
      ip        = var.ip_addresses["nfs-server"]
      snippet   = templatefile("${path.module}/cloud-init/nfs-server.yaml", { ssh_public_keys = var.ssh_public_keys })
      cores     = 2
      memory    = 4096
      disk_size = 600
      tags      = ["node", "homelab", "storage"]
    }
    "mgmt-plane" = {
      id        = 102
      ip        = var.ip_addresses["mgmt-plane"]
      snippet   = templatefile("${path.module}/cloud-init/mgmt-plane.yaml", { ssh_public_keys = var.ssh_public_keys })
      cores     = 4
      memory    = 16384
      disk_size = 60
      tags      = ["node", "homelab", "cluster-management"]
    }
  }

  containers = {
    "garage" = {
      id             = 200
      hostname       = "garage"
      ip             = var.ip_addresses["garage"]
      cores          = 2
      memory         = 2048
      disk_size      = 8
      data_disk_size = 200
      tags           = ["container", "homelab", "storage"]
    }
  }
}
