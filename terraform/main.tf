terraform {
  required_version = ">= 1.5"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.44"
    }
  }
}

provider "proxmox" {
  endpoint    = var.proxmox_api_url
  api_token   = var.proxmox_token
  insecure    = true   # set to false if you have valid certs
  # If you prefer username/password:
  # username = var.proxmox_user
  # password = var.proxmox_password
}

resource "proxmox_vm_qemu" "vm" {
  name        = var.vm_name
  target_node = var.node_name
  vmid        = var.vm_id
  memory      = var.memory
  cores       = var.cores
  scsihw      = "virtio-scsi-pci"
  bootdisk    = "scsi0"

  # === Disk ===
  disk {
    size        = "${var.disk_size_gb}G"
    type        = "scsi"
    storage     = "local-lvm"   # adjust to your storage name
    iothread    = true
    ssd         = true
    discard     = "on"
  }

  # === Cloud‑Init (user‑data) ===
  # Proxmox provides a built‑in cloud‑init drive that can inject SSH keys,
  # static IP, etc. Very handy for getting Ansible in right away.
  ciuser = "terraform"
  cipassword = ""               # leave empty – we’ll use SSH keys only
  sshkeys = var.ssh_public_key

  # Optional static IP via cloud‑init (requires guest OS that supports it,
  # such as Ubuntu Cloud images). If you leave this empty, the VM will use DHCP.
  ipconfig0 = var.net_ip_cidr != "" ? "ip=${var.net_ip_cidr},gw=192.168.10.1" : ""

  # === Network ===
  network {
    model  = "virtio"
    bridge = var.net_bridge
    tag    = 0
  }

  # === Lifecycle ===
  # If you plan to re‑run this many times, you may want to adopt existing VMs
  # instead of destroying+re‑creating each run.
  lifecycle {
    create_before_destroy = true
  }
}
