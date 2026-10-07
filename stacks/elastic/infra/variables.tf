# TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

variable "proxmox_api_token" {
  description = "Proxmox API token, form user@realm!tokenid=secret (terraform@pve!terraform)"
  sensitive   = true
  type        = string
}
variable "cipassword" {
  description = "cloud-init user password"
  sensitive   = true
  type        = string
}
