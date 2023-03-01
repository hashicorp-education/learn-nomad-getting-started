# Values for retry_join, and ip_address are
# placed here during Terraform setup and come from the 
# ../shared/data-scripts/user-data-client.sh script

data_dir  = "/opt/nomad/data"
bind_addr = "0.0.0.0"
datacenter = "dc1"

advertise {
  http = "IP_ADDRESS"
  rpc  = "IP_ADDRESS"
  serf = "IP_ADDRESS"
}

acl {
  enabled = true
}

client {
  enabled = true
  options {
    "driver.raw_exec.enable"    = "1"
    "docker.privileged.enabled" = "true"
  }
  server_join {
    retry_join = ["RETRY_JOIN"]
  }
}