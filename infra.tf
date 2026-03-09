# Download once, reused by each VM
resource "proxmox_virtual_environment_download_file" "ubuntu_image" {
  node_name    = var.node_name
  content_type = "import"
  datastore_id = "local"
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "noble-server-cloudimg-amd64.qcow2"
}

# Upload per-VM cloud-init snippets
resource "proxmox_virtual_environment_file" "cloud_init" {
  for_each     = local.nodes
  node_name    = var.node_name
  content_type = "snippets"
  datastore_id = "local"

  source_raw {
    data      = each.value.snippet
    file_name = "${each.key}.yaml"
  }
}

# Download Debian 13 LXC template 
resource "proxmox_virtual_environment_download_file" "debian_lxc_template" {
  node_name    = var.node_name
  content_type = "vztmpl"
  datastore_id = "local"
  url          = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"
  file_name    = "debian-13-standard_13.1-2_amd64.tar.zst"
}

# Create LXC container for garage
resource "proxmox_virtual_environment_container" "garage" {
  node_name    = var.node_name
  vm_id        = local.containers["garage"].id
  tags         = local.containers["garage"].tags
  unprivileged = true

  features {
    nesting = true
  }

  initialization {
    hostname = local.containers["garage"].hostname

    ip_config {
      ipv4 {
        address = "${local.containers["garage"].ip}/24"
        gateway = var.gateway_ip
      }
    }

    user_account {
      keys = var.ssh_public_keys
    }
  }

  cpu {
    cores = local.containers["garage"].cores
  }

  memory {
    dedicated = local.containers["garage"].memory
  }

  # Root OS disk (minimal size)
  disk {
    datastore_id = "local-lvm"
    size         = local.containers["garage"].disk_size
  }

  # Separate data volume for garage object storage
  mount_point {
    volume = "local-lvm"
    size   = "${local.containers["garage"].data_disk_size}G"
    path   = "/mnt/data"
  }

  network_interface {
    name   = "veth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.debian_lxc_template.id
    type             = "debian"
  }
}

# Create VMs for nodes
resource "proxmox_virtual_environment_vm" "nodes" {
  for_each  = local.nodes
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
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk_size
    import_from  = proxmox_virtual_environment_download_file.ubuntu_image.id
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