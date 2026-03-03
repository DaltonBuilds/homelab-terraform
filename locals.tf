locals {
    nodes = {
        "gimli" = {
            id      = 101
            ip      = var.ip_addresses["gimli"]
            snippet = file("${path.module}/cloud-init/gimli.yaml")
            cores   = 4
            memory  = 8192
            disk_size = 60
            tags    = ["node", "homelab", "k3s-worker", "cluster-workloads"]
        }
        "nfs-server" = {
            id      = 102
            ip      = var.ip_addresses["nfs-server"]
            snippet = file("${path.module}/cloud-init/nfs-server.yaml")
            cores   = 2
            memory  = 4096
            disk_size = 800
            tags    = ["node", "homelab", "storage"]
        }
        "mgmt-plane" = {
            id      = 103
            ip      = var.ip_addresses["mgmt-plane"]
            snippet = file("${path.module}/cloud-init/mgmt-plane.yaml")
            cores   = 4
            memory  = 12288
            disk_size = 80
            tags    = ["node", "homelab", "cluster-management"]
        }
    }
}
