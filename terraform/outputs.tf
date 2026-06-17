output "vm_id" {
  value = proxmox_vm_qemu.vm.vmid
}

output "vm_name" {
  value = proxmox_vm_qemu.vm.name
}

# The IP is a little tricky – there is no direct TF attribute.
# We can extract it from the cloud‑init status after the VM boots.
# For a quick demo we expose the *target* IP that we *expect* to be used.
output "target_ip" {
  description = "IP address that Ansible should use. Falls back to DHCP if net_ip_cidr is empty."
  value = var.net_ip_cidr != "" ? split("/", var.net_ip_cidr)[0] :
          # DHCP case – we try to read the IP from the guest agent (requires guest‑agent installed).
          # If it fails we just return an empty string; the wrapper script will poll until it appears.
          ""
}
