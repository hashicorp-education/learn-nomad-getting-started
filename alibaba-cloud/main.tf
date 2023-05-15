provider "alicloud" {
  region = var.region
}

data "alicloud_zones" "default" {
  available_resource_creation = "VSwitch"
}

locals {
  retry_join = "provider=aliyun tag_key=NomadJoinTag tag_value=auto-join"
}

resource "alicloud_vpc" "vpc" { 
  vpc_name   = "${var.name}-vpc"
  cidr_block = "172.16.0.0/12"
}

resource "alicloud_vswitch" "vswitch" {
  vswitch_name   = "${var.name}-vswitch"
  vpc_id       = alicloud_vpc.vpc.id
  cidr_block   = "172.16.0.0/24"
  zone_id      = data.alicloud_zones.default.zones.0.id
}

resource "alicloud_security_group" "nomad_ui" {
  name   = "${var.name}-nomad-ui"
  vpc_id = alicloud_vpc.vpc.id
}

resource "alicloud_security_group_rule" "nomad_ui_ingress" {
  type              = "ingress"
  ip_protocol       = "tcp"
  policy            = "accept"
  port_range        = "4646/4646"
  priority          = 1
  security_group_id = alicloud_security_group.nomad_ui.id
  cidr_ip           = var.allowlist_ip
}

resource "alicloud_security_group_rule" "nomad_ui_egress" {
  type              = "egress"
  ip_protocol       = "all"
  policy            = "accept"
  port_range        = "-1/-1"
  priority          = 1
  security_group_id = alicloud_security_group.nomad_ui.id
  cidr_ip           = "0.0.0.0/0"
}

resource "alicloud_security_group" "nomad_ssh" {
  name   = "${var.name}-ssh"
  vpc_id = alicloud_vpc.vpc.id
}

resource "alicloud_security_group_rule" "nomad_ssh_ingress" {
  type              = "ingress"
  ip_protocol       = "tcp"
  policy            = "accept"
  port_range        = "22/22"
  priority          = 1
  security_group_id = alicloud_security_group.nomad_ssh.id
  cidr_ip           = var.allowlist_ip
}

resource "alicloud_security_group_rule" "nomad_ssh_egress" {
  type              = "egress"
  ip_protocol       = "all"
  policy            = "accept"
  port_range        = "-1/-1"
  priority          = 1
  security_group_id = alicloud_security_group.nomad_ssh.id
  cidr_ip           = "0.0.0.0/0"
}

resource "alicloud_security_group" "clients" {
  name   = "${var.name}-clients-ingress"
  vpc_id = alicloud_vpc.vpc.id
}

resource "alicloud_security_group_rule" "clients_ingress_1" {
  type              = "ingress"
  ip_protocol       = "all"
  policy            = "accept"
  port_range        = "5000/5000"
  priority          = 1
  security_group_id = alicloud_security_group.clients.id
  cidr_ip           = "0.0.0.0/0"
}

# Add additional application ingress rules here
# These rules are applied only to the client nodes
# resource "alicloud_security_group_rule" "clients_ingress_2" {
#   type              = "ingress"
#   ip_protocol       = "tcp"
#   nic_type          = "internet"
#   policy            = "accept"
#   port_range        = "80/80"
#   priority          = 1
#   security_group_id = alicloud_security_group.default.id
#   cidr_ip           = "0.0.0.0/0"
# }

resource "alicloud_security_group_rule" "clients_egress" {
  type              = "egress"
  ip_protocol       = "all"
  policy            = "accept"
  port_range        = "-1/-1"
  priority          = 1
  security_group_id = alicloud_security_group.clients.id
  cidr_ip           = "0.0.0.0/0"
}

data "alicloud_images" "ubuntu" {
  most_recent      = true
  name_regex       = "^ubuntu"
  architecture     = "x86_64"
  owners           = "system"
}

resource "alicloud_instance" "server" {
  vswitch_id = alicloud_vswitch.vswitch.id
  security_groups = [alicloud_security_group.nomad_ui.id, alicloud_security_group.nomad_ssh.id]
  internet_max_bandwidth_out = 100
  instance_type              = var.server_instance_type
  image_id                   = data.alicloud_images.ubuntu.images.0.id
  count = var.server_count

  key_name = alicloud_ecs_key_pair.generated_key.key_name

  role_name = alicloud_ram_role.instance_role.name

  tags = {
    Name = "${var.name}-server-${count.index}"
    NomadJoinTag = "auto-join"
    NomadType = "server"
  }

connection {
    type        = "ssh"
    user        = "root"
    private_key = tls_private_key.private_key.private_key_pem
    host        = self.public_ip
}

provisioner "remote-exec" {
    inline = ["sudo mkdir -p /ops", "sudo chmod 777 -R /ops"]
  }

provisioner "file" {
    source      = "../shared"
    destination = "/ops"
  }

  user_data    = "${templatefile("../shared/data-scripts/user-data-server.sh", {
      region                    = var.region
      cloud_env                 = "alicloud"
      server_count              = "${var.server_count}"
      retry_join                = local.retry_join
      nomad_version             = var.nomad_version
  })}"
}

resource "alicloud_instance" "client" {
  vswitch_id = alicloud_vswitch.vswitch.id
  security_groups = [alicloud_security_group.nomad_ui.id, alicloud_security_group.nomad_ssh.id, alicloud_security_group.clients.id]
  internet_max_bandwidth_out = 100
  instance_type              = var.client_instance_type
  image_id                   = data.alicloud_images.ubuntu.images.0.id
  count = var.client_count

  key_name = alicloud_ecs_key_pair.generated_key.key_name

  role_name = alicloud_ram_role.instance_role.name

  tags = {
    Name = "${var.name}-client-${count.index}"
    NomadJoinTag = "auto-join"
    NomadType = "client"
  }

connection {
    type        = "ssh"
    user        = "root"
    private_key = tls_private_key.private_key.private_key_pem
    host        = self.public_ip
}

provisioner "remote-exec" {
    inline = ["sudo mkdir -p /ops", "sudo chmod 777 -R /ops"]
  }

provisioner "file" {
    source      = "../shared"
    destination = "/ops"
  }

  user_data    = "${templatefile("../shared/data-scripts/user-data-client.sh", {
      region                    = var.region
      cloud_env                 = "alicloud"
      retry_join                = local.retry_join
      nomad_version             = var.nomad_version
  })}"
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "alicloud_ecs_key_pair" "generated_key" {
  key_pair_name           = "tf-key"
  public_key         = tls_private_key.private_key.public_key_openssh
}

# Uncomment the private key resource below if you want to SSH to any of the instances
# Run init and apply again after uncommenting:
# terraform init && terraform apply
# Then SSH with the tf-key.pem file:
# ssh -i tf-key.pem root@INSTANCE_PUBLIC_IP

resource "local_file" "tf_pem" {
  filename = "${path.module}/tf-key.pem"
  content = tls_private_key.private_key.private_key_pem
  file_permission = "0400"
}

resource "alicloud_ram_role" "instance_role" {
  name = "${var.name}-instance-role"
  document    = <<EOF
  {
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
          "Service": [
            "ecs.aliyuncs.com"
          ]
        }
      }
    ],
    "Version": "1"
  }
  EOF
}

resource "alicloud_ram_policy" "auto_discover_cluster" {
  policy_name     = "${var.name}-auto-discover-cluster"
  policy_document = <<EOF
  {
    "Statement": [
      {
        "Action": [
          "ecs:DescribeInstances"
        ],
        "Effect": "Allow",
        "Resource": ["*"]
      }
    ],
      "Version": "1"
  }
  EOF
}

resource "alicloud_ram_role_policy_attachment" "attach" {
  policy_name = alicloud_ram_policy.auto_discover_cluster.name
  policy_type = alicloud_ram_policy.auto_discover_cluster.type
  role_name   = alicloud_ram_role.instance_role.name
}