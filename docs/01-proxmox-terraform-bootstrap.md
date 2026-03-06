# Proxmox + Terraform Bootstrap: Lessons Learned

**Date:** March 2026  
**Provider:** [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest) v0.97.1  
**Goal:** Provision 3 Ubuntu VMs (gimli, nfs-server, mgmt-plane) and 1 Alpine LXC container (garage) on a single Proxmox node using Terraform.

---

## What We Were Building

| Resource | Type | ID | Purpose |
|---|---|---|---|
| `gimli` | VM (Ubuntu 24.04) | 100 | k3s worker node |
| `nfs-server` | VM (Ubuntu 24.04) | 101 | NFS/storage node |
| `mgmt-plane` | VM (Ubuntu 24.04) | 102 | k3s management node |
| `garage` | LXC (Alpine 3.23) | 200 | Object storage (Garage S3) |

Cloud-init snippets were uploaded per-VM to handle package installs and service setup at first boot.

---

## Challenge 1: API Token Permissions (HTTP 403)

### Symptom

```
Error: error listing files from datastore local: received an HTTP 403 response
- Reason: Permission check failed (/storage/local, Datastore.Audit|Datastore.AllocateSpace)

Error: Could not get file metadata...received an HTTP 403 response
- Reason: Permission check failed
```

### Root Cause

Two separate permission issues were compounding:

1. **Wrong API token format/variable name.** The `bpg/proxmox` provider reads the token from `PROXMOX_VE_API_TOKEN`, not `PROXMOX_API_TOKEN`. The token format must be: `user@realm!tokenid=secret`

2. **Proxmox "Privilege Separation" on the API token.** When privilege separation is enabled on a token, the token's effective permissions are the *intersection* of the token's ACLs and the parent user's ACLs. Granting the token Administrator on a storage path has no effect if the parent user has no permissions — they must both be granted, or privilege separation must be disabled.

### Solution

- Set the correct environment variable before running `terraform apply`:
  ```bash
  export PROXMOX_VE_API_TOKEN='root@pam!tokenid=your-secret-here'
  ```

- In Proxmox UI: Datacenter → Permissions → API Tokens → uncheck **Privilege Separation** on the token, OR ensure the parent user also has the required ACL on the same paths.

### Minimum ACL Scope (TODO: test and refine)

Rather than using Administrator everywhere, the minimum required privileges for this setup are believed to be:

| Path | Privileges |
|---|---|
| `/storage/local` | `Datastore.Audit`, `Datastore.AllocateSpace` |
| `/storage/local-lvm` | `Datastore.Audit`, `Datastore.AllocateSpace` |
| `/nodes/<node>` | `Sys.Audit` |
| `/` (root, for VM/CT create) | `VM.Allocate`, `VM.Config.Disk`, `VM.Config.CPU`, `VM.Config.Memory`, `VM.Config.Network`, `VM.Config.Options`, `VM.PowerMgmt`, `VM.Audit` |

> These are estimates based on provider documentation and should be verified — a good follow-up is to create a scoped role with only these privileges and confirm a clean `terraform apply`.

---

## Challenge 2: SSH Authentication Failure for Snippet Uploads

### Symptom

```
Error: failed to open SSH client: unable to authenticate user "" over SSH to "192.168.40.50:22"
...attempted methods [none password], no supported methods remain
```

Then, after setting `PROXMOX_VE_SSH_USERNAME`:

```
Error: failed to open SSH client: unable to authenticate user "root" over SSH to "192.168.40.50:22"
...attempted methods [none password], no supported methods remain
```

### Root Cause

The `bpg/proxmox` provider uploads certain file types — specifically `snippets` (cloud-init) — via **SSH/SFTP**, not the Proxmox HTTP API. This is a known provider limitation documented upstream:

> *"Due to limitations in the Proxmox VE API, certain files (snippets, backups) need to be uploaded using SFTP. This requires the use of a PAM account."*

Two things were wrong:

1. No SSH username was configured at all, so the provider attempted SSH as an empty string (`""`).
2. Even after setting `PROXMOX_VE_SSH_USERNAME=root`, the provider was still only attempting `[none password]` — meaning it never tried public key auth. This happens because the `bpg` provider requires `agent = true` to be **explicitly declared** in the provider `ssh {}` block; it does not default to using the agent.

Additionally, `ssh-agent` must be running locally with the key loaded, and `SSH_AUTH_SOCK` must be set in the shell session where `terraform apply` runs.

### Diagnostic Commands

```bash
# Check if agent has a key loaded
ssh-add -L

# Verify SSH_AUTH_SOCK is set (empty = agent not wired up in this session)
echo $SSH_AUTH_SOCK

# Start agent and load key if needed
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/proxmox_tf
```

### Solution

**Step 1:** Generate a dedicated SSH key for Terraform → Proxmox:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/proxmox_tf -C "terraform-proxmox"
```

**Step 2:** Add the public key to Proxmox root's authorized_keys:
```bash
# On the Proxmox host:
cat ~/.ssh/proxmox_tf.pub >> /root/.ssh/authorized_keys
```

**Step 3:** Load the key into your local agent before applying:
```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/proxmox_tf
```

**Step 4:** Add an explicit `ssh` block to `main.tf`:
```hcl
provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = true

  ssh {
    agent    = true
    username = "root"
  }
}
```

> The `username` here is the **Linux PAM user on the Proxmox host**, not the Proxmox realm user. Snippets can only be uploaded by a PAM-backed account (e.g. `root`).

**Alternative (no ssh-agent):** Set the password instead:
```bash
export PROXMOX_VE_SSH_USERNAME=root
export PROXMOX_VE_SSH_PASSWORD=your-root-password
```

---

## Challenge 3: LXC Template — Wrong URL and Wrong File Format

### Symptom 1: Container fails to create

```
Error: task failed... command 'lxc-usernsexec ... tar xpf - -J ... exit code 2'
```

`tar` exit code 2 is a fatal extraction error.

### Symptom 2: Template file is not actually an archive

```bash
# Run on Proxmox host to inspect what was actually downloaded:
xz -t /var/lib/vz/template/cache/alpine-3.23-default_20260116_amd64.tar.xz
# xz: File format not recognized

file /var/lib/vz/template/cache/alpine-3.23-default_20260116_amd64.tar.xz
# HTML document, ASCII text  ← the "template" was just an HTML page
```

### Root Cause

The `url` in `infra.tf` was set to just the base domain:
```hcl
url = "http://download.proxmox.com"   # wrong — this is a webpage, not a file
```

The provider fetched the HTML homepage of `download.proxmox.com`, saved it with a `.tar.xz` extension, and Proxmox then tried to extract it as an LXC template — which failed immediately.

### Solution

Use the full path to the actual template file:
```hcl
resource "proxmox_virtual_environment_download_file" "alpine_lxc_template" {
  node_name    = var.node_name
  content_type = "vztmpl"
  datastore_id = "local"
  url          = "http://download.proxmox.com/images/system/alpine-3.23-default_20260116_amd64.tar.xz"
  file_name    = "alpine-3.23-default_20260116_amd64.tar.xz"
}
```

> Tip: Find valid template URLs by using the Proxmox UI template browser (node → local → CT Templates → Templates) and inspecting the download URLs it uses — these come directly from the Proxmox mirror list.

### Why One Resource Was Destroyed on Final Apply

The final successful `terraform apply` showed `8 added, 0 changed, 1 destroyed`. The destroy was expected: the `garage` container had been partially created in an earlier failed run (with the bad template), so it existed in Terraform state. Fixing the template URL is an immutable property change on a container — Terraform destroys the old resource and recreates it. This is normal and correct behavior.

---

## Summary of Environment Variables Required

Set these locally before each `terraform apply`. Do not commit them.

```bash
export PROXMOX_VE_API_TOKEN='root@pam!tokenid=your-secret-here'
export PROXMOX_VE_SSH_USERNAME='root'

# Then load your SSH key if not already in agent:
ssh-add ~/.ssh/proxmox_tf
```

---

## Key Takeaways

| # | Lesson |
|---|---|
| 1 | `bpg/proxmox` uses `PROXMOX_VE_API_TOKEN`, not `PROXMOX_API_TOKEN` |
| 2 | Proxmox API token privilege separation means token ACLs AND parent user ACLs both apply |
| 3 | Snippet/cloud-init uploads go over SSH/SFTP, not the API — a PAM account is required |
| 4 | The provider `ssh {}` block requires `agent = true` explicitly; it does not default to using ssh-agent |
| 5 | `SSH_AUTH_SOCK` must be set in the same shell session that runs `terraform apply` |
| 6 | Always verify downloaded template files are valid archives before applying (`xz -t`, `file`) |
| 7 | LXC templates must be full rootfs archives from a proper source — not cloud disk images |
