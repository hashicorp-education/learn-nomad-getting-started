variable "name" {
  description = "Prefix used to name various infrastructure components. Alphanumeric characters only."
  default     = "nomad"
}

variable "location" {
  description = "The Azure region to deploy to."
}

variable "subscription_id" {
  description = "The Azure subscription ID to use."
}

variable "client_id" {
  description = "The Azure client ID to use."
}

variable "client_secret" {
  description = "The Azure client secret to use."
}

variable "tenant_id" {
  description = "The Azure tenant ID to use."
}

variable "retry_join" {
  description = "Used by Nomad to automatically form a cluster."
  type        = string
}

variable "allowlist_ip" {
  description = "IP to allow access for the security groups (set 0.0.0.0/0 for world)"
  default     = "0.0.0.0/0"
}

variable "server_instance_type" {
  description = "The Azure VM instance type to use for servers."
  default     = "Standard_B2s"
}

variable "client_instance_type" {
  description = "The Azure VM type to use for clients."
  default     = "Standard_B2s"
}

variable "server_count" {
  description = "The number of servers to provision."
  default     = "3"
}

variable "client_count" {
  description = "The number of clients to provision."
  default     = "2"
}

variable "root_block_device_size" {
  description = "The volume size of the root block device."
  default     = 16
}

variable "nomad_version" {
  description = "The version of the Nomad binary to install."
  default     = "1.5.0"
}