resource "proxmox_virtual_environment_vm" "signal-api" {
  name      = "signal-api"
  node_name = "pve01"

  # should be true if qemu agent is not installed / enabled on the VM
  stop_on_destroy = true

  initialization {
    ip_config {
      ipv4 {
          address = "172.16.100.101/24"
          gateway = "172.16.100.1"
      }
    }
    user_account {
      username = "< USER NAME >"
      password = "< PASSWORD  >"
    }
  }
  network_device {
    bridge       = "vmbr1"
  }

  serial_device {}

  disk {
    datastore_id = "local-lvm"
    file_id      = <IMAGE ID>
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 20
  }
}
