# Values for server_count, retry_join, and ip_address are
# placed here during Terraform setup and come from the 
# ../shared/data-scripts/user-data-server.sh script

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

server {
  enabled          = true
  bootstrap_expect = SERVER_COUNT

  server_join {
    retry_join = ["RETRY_JOIN"]
  }
}