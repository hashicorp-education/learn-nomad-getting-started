variable "name" {
  description = "Prefix used to name various infrastructure components. Alphanumeric characters only."
  default     = "nomad"
}

variable "region" {
  description = "The AWS region to deploy to."
}

variable "retry_join" {
  description = "Used by Nomad to automatically form a cluster."
  type        = string
  default     = "provider=aws tag_key=NomadJoinTag tag_value=auto-join"
}

variable "allowlist_ip" {
  description = "IP to allow access for the security groups (set 0.0.0.0/0 for world)"
  default     = "0.0.0.0/0"
}

variable "server_instance_type" {
  description = "The AWS instance type to use for servers."
  default     = "t2.micro"
}

variable "client_instance_type" {
  description = "The AWS instance type to use for clients."
  default     = "t2.micro"
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
  default     = "1.4.3"
}