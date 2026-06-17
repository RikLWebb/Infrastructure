#!/usr/bin/env bash
#=====================================================================
# deploy.sh
#
# 1️⃣ Run Terraform to create a VM on Proxmox.
# 2️⃣ Grab the IP address (static or DHCP) from Terraform output.
# 3️⃣ Write a temporary Ansible inventory.
# 4️⃣ Run the Ansible playbook against the new host.
#
# Requirements:
#   * terraform  >= 1.5
#   * ansible    >= 2.12
#   * jq         (for parsing JSON)
#   * ssh-agent  (so Ansible can use your private key)
#=====================================================================

set -euo pipefail

# --------------------------------------------------------------------
# CONFIGURATION (you can also export these as env vars before calling the script)
# --------------------------------------------------------------------
TF_DIR="./terraform"
ANSIBLE_DIR="./ansible"
ANSIBLE_PLAYBOOK="${ANSIBLE_DIR}/site.yml"
ANSIBLE_INVENTORY="${ANSIBLE_DIR}/inventory.ini"
SSH_PRIVATE_KEY="${HOME}/.ssh/id_ed25519_proxmox"    # adjust if you use a different key
SSH_USER="terraform"                               # matches ciuser in TF
MAX_SSH_WAIT=300                                   # seconds to wait for VM to be reachable

# --------------------------------------------------------------------
# Helper functions
# --------------------------------------------------------------------
log() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# Wait until a given IP answers SSH (used for DHCP case)
wait_for_ssh() {
  local ip=$1
  local deadline=$((SECONDS + MAX_SSH_WAIT))
  while (( SECONDS < deadline )); do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "${SSH_PRIVATE_KEY}" "${SSH_USER}@${ip}" "echo ready" &>/dev/null; then
      log "SSH is up on ${ip}"
      return 0
    fi
    sleep 5
  done
  error "Timed out waiting for SSH on ${ip}"
}

# --------------------------------------------------------------------
# 1️⃣ Initialise / apply Terraform
# --------------------------------------------------------------------
log "=== Terraform init ==="
terraform -chdir="${TF_DIR}" init -input=false

log "=== Terraform apply (auto‑approve) ==="
terraform -chdir="${TF_DIR}" apply -auto-approve -input=false

# --------------------------------------------------------------------
# 2️⃣ Grab outputs
# --------------------------------------------------------------------
log "=== Reading Terraform outputs ==="
VM_ID=$(terraform -chdir="${TF_DIR}" output -json vm_id | jq -r .)
VM_NAME=$(terraform -chdir="${TF_DIR}" output -json vm_name | jq -r .)
STATIC_IP=$(terraform -chdir="${TF_DIR}" output -json target_ip | jq -r .)

if [[ -n "${STATIC_IP}" && "${STATIC_IP}" != "null" ]]; then
  TARGET_IP="${STATIC_IP}"
  log "Static IP detected from TF var: ${TARGET_IP}"
else
  # DHCP – we need to poll the Proxmox API (or guest‑agent) until an IP appears.
  # The most reliable way is to use the Proxmox API to query the VM’s network devices.
  # This requires an API token – reuse the same token we passed to Terraform.
  # We'll read the token from the TF variable, so export it first.
  PROXMOX_API_URL=$(terraform -chdir="${TF_DIR}" output -json proxmox_api_url 2>/dev/null || true)
  if [[ -z "${PROXMOX_API_URL}" ]]; then
    # fallback: read from tfvars or env var
    PROXMOX_API_URL=$(grep '^proxmox_api_url' "${TF_DIR}/terraform.tfvars" | cut -d'=' -f2 | tr -d ' "')
  fi
  # The provider automatically stores the token in the state, but the easiest is to just reuse the env var:
  PROXMOX_TOKEN="${PROXMOX_TOKEN:-}"
  if [[ -z "${PROXMOX_TOKEN}" ]]; then
    error "Cannot determine Proxmox API token for DHCP IP lookup. Export PROXMOX_TOKEN or set a static IP."
  fi

  log "No static IP – attempting to discover DHCP address via Proxmox API..."
  # NOTE: This uses the Proxmox “/nodes/<node>/qemu/<vmid>/agent/network-get-ifaces” endpoint.
  # The VM must have the QEMU guest‑agent installed and running (most cloud images have it).
  ENDPOINT="${PROXMOX_API_URL%/api2/json}/nodes/${node_name}/qemu/${VM_ID}/agent/network-get-ifaces"

  # Helper to request once
  query_ip() {
    curl -s -k -H "Authorization: PVEAPIToken=${PROXMOX_TOKEN}" "${ENDPOINT}" |
      jq -r '.data[]?.["ip-addresses"][]?.["ip-address"]' |
      grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' |
      head -n1
  }

  # Poll every 5 seconds, up to MAX_SSH_WAIT seconds
  deadline=$((SECONDS + MAX_SSH_WAIT))
  while (( SECONDS < deadline )); do
    TARGET_IP=$(query_ip || true)
    if [[ -n "${TARGET_IP}" ]]; then
      log "Discovered DHCP IP: ${TARGET_IP}"
      break
    fi
    sleep 5
  done

  if [[ -z "${TARGET_IP}" ]]; then
    error "Failed to discover IP address for VM ${VM_ID} within ${MAX_SSH_WAIT}s"
  fi
fi

# --------------------------------------------------------------------
# 3️⃣ Build a temporary Ansible inventory
# --------------------------------------------------------------------
log "=== Writing Ansible inventory (${ANSIBLE_INVENTORY}) ==="
cat > "${ANSIBLE_INVENTORY}" <<EOF
[terraform_vms]
${TARGET_IP} ansible_user=${SSH_USER} ansible_ssh_private_key_file=${SSH_PRIVATE_KEY}
EOF

# --------------------------------------------------------------------
# 4️⃣ Make sure SSH can talk to the host (useful for DHCP case)
# --------------------------------------------------------------------
log "=== Waiting for SSH on ${TARGET_IP} ==="
wait_for_ssh "${TARGET_IP}"

# --------------------------------------------------------------------
# 5️⃣ Run the Ansible playbook
# --------------------------------------------------------------------
log "=== Running Ansible playbook (${ANSIBLE_PLAYBOOK}) ==="
ansible-playbook -i "${ANSIBLE_INVENTORY}" "${ANSIBLE_PLAYBOOK}"

log "=== DONE! VM ${VM_NAME} (ID=${VM_ID}) has been provisioned and configured. ==="
