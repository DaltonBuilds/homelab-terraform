# homelab-terraform

Terraform configuration for provisioning all VMs and LXC containers on a Proxmox homelab using the [bpg/proxmox](https://github.com/bpg/terraform-provider-proxmox) provider.

This is one of three repos that make up my homelab infrastructure. Terraform handles the compute layer — once resources are up, [homelab-ansible](https://github.com/DaltonBuilds/homelab-ansible) handles OS configuration and [homelab-gitops](https://github.com/DaltonBuilds/homelab-gitops) handles everything running in Kubernetes.

## Resources

| Resource | Type | vCPU | RAM | Disk | IP |
|---|---|---|---|---|---|
| nfs-server | VM (Ubuntu 24.04) | 2 | 4GB | 600GB | 192.168.40.51 |
| mgmt-plane | VM (Ubuntu 24.04) | 4 | 16GB | 60GB | 192.168.40.52 |
| gimli | VM (Ubuntu 24.04) | 4 | 8GB | 50GB | 192.168.40.33 |
| garage | LXC (Debian 13) | 2 | 2GB | 8GB + 200GB data | 192.168.40.53 |

The three bare-metal k3s nodes (gandalf, aragorn, legolas) are not managed here — they're physical machines and also configured by Ansible.

## Structure

```
homelab-terraform/
├── main.tf              # Provider config (bpg/proxmox)
├── infra.tf             # VM and LXC resource definitions
├── locals.tf            # Node specs and configuration locals
├── variables.tf         # Variable definitions
├── outputs.tf           # IP addresses and VM IDs
├── cloud-init/          # Per-VM cloud-init templates
└── docs/
    └── 01-proxmox-terraform-bootstrap.md
```

## Stack

- **Provider:** bpg/proxmox v0.97+
- **Auth:** Proxmox API token (not root credentials)
- **VM provisioning:** Cloud-init for hostname, static IP, SSH key injection, package bootstrapping
- **State:** Remote — GCS bucket with versioning and native state locking

## Usage

State is stored in a GCS bucket and locked automatically on apply. GCP credentials must be available in the environment (e.g. `GOOGLE_APPLICATION_CREDENTIALS` or `gcloud auth application-default login`).

```bash
# Proxmox credentials via environment variable or terraform.tfvars (gitignored)
terraform init
terraform plan
terraform apply
```

Secrets (`terraform.tfvars`) are not committed. See `variables.tf` for required inputs.
