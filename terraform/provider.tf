provider "proxmox" {
  # endpoint, api_token and the insecure flag are read from the environment
  # (PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN, PROXMOX_VE_INSECURE) - see
  # .env.example. Nothing sensitive lives in this repo.
}
