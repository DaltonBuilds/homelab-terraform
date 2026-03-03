# Download once, reused by each VM
resource "proxmox_virtual_environment_download_file" "ubuntu_image" {
    node_name = var.node_name
    content_type = "import"
    datastore_id = "local"
    url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    file_name = "noble-server-cloudimg-amd64.qcow2"
}

# Upload per-VM cloud-init snippets
resource "proxmox_virtual_environment_file" "cloud_init" {
  for_each = local.nodes
  node_name = var.node_name
  content_type   = "snippets"
  datastore_id   = "local"

  source_raw {
    data = each.value.snippet
    file_name = "${each.key}.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "nodes" {
    for_each = local.nodes
    name      = each.key
    vm_id     = each.value.id
    node_name = var.node_name
    tags      = each.value.tags

    agent {
        enabled = true
    }
    
    stop_on_destroy = true

    cpu {
        cores = each.value.cores
        type = "x86-64-v2-AES"
    }

    memory {
        dedicated = each.value.memory
    }

    disk {
        datastore_id = "local-lvm"
        interface = "scsi0"
        size = each.value.disk_size
        import_from = proxmox_virtual_environment_download_file.ubuntu_image.id
    }

    network_device {
        bridge = "vmbr0"
    }

    operating_system {
        type = "l26"
    }

    initialization {
        user_data_file_id = proxmox_virtual_environment_file.cloud_init[each.key].id

        ip_config {
            ipv4 {
                address = "${each.value.ip}/24"
                gateway = var.gateway_ip
            }
        }
    }
}