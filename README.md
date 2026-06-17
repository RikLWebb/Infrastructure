# 1. Make sure you have the required vars exported (or edit terraform/terraform.tfvars):
export PROXMOX_TOKEN="terraform-token-id:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
# If you stored the token in terraform.tfvars you can omit the export.

# 2. (Optional) Load your SSH key into ssh-agent so Ansible can use it without a password prompt:
ssh-add ~/.ssh/id_ed25519_proxmox

# 3. Run the script:
chmod +x deploy.sh
./deploy.sh
