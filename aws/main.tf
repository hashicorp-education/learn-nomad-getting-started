terraform {
  required_version = ">= 0.12"
}

provider "aws" {
  region = var.region
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "nomad_ui_ingress" {
  name   = "${var.name}-ui-ingress"
  vpc_id = data.aws_vpc.default.id

  # Nomad
  ingress {
    from_port       = 4646
    to_port         = 4646
    protocol        = "tcp"
    cidr_blocks     = [var.allowlist_ip]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ssh_ingress" {
  name   = "${var.name}-ssh-ingress"
  vpc_id = data.aws_vpc.default.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowlist_ip]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "allow_all_internal" {
  name   = "${var.name}-allow-all-internal"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }
}

resource "aws_security_group" "clients_ingress" {
  name   = "${var.name}-clients-ingress"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Add application ingress rules here
  # These rules are applied only to the client nodes

  # nginx example
  # ingress {
  #   from_port   = 80
  #   to_port     = 80
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


data "aws_ami" "ubuntu" {
  most_recent      = true
  owners           = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "tf-key"
  public_key = tls_private_key.private_key.public_key_openssh
}

resource "aws_instance" "server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.server_instance_type
  key_name               = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.nomad_ui_ingress.id, aws_security_group.ssh_ingress.id, aws_security_group.allow_all_internal.id]
  count                  = var.server_count

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.private_key.private_key_pem
    host        = self.public_ip
  }

  # NomadJoinTag is necessary for nodes to automatically join the cluster
  tags = merge(
    {
      "Name" = "${var.name}-server-${count.index}"
    },
    {
      "NomadJoinTag" = "auto-join"
    },
    {
      "NomadType" = "server"
    }
  )

  root_block_device {
    volume_type           = "gp2"
    volume_size           = var.root_block_device_size
    delete_on_termination = "true"
  }

  provisioner "remote-exec" {
    inline = ["sudo mkdir -p /ops", "sudo chmod 777 -R /ops"]
  }

  provisioner "file" {
    source      = "../shared"
    destination = "/ops"
  }

  user_data = templatefile("../shared/data-scripts/user-data-server.sh", {
    server_count              = var.server_count
    region                    = var.region
    cloud_env                 = "aws"
    retry_join                = var.retry_join
    nomad_version             = var.nomad_version
  })
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

  metadata_options {
    http_endpoint          = "enabled"
    instance_metadata_tags = "enabled"
  }
}

resource "aws_instance" "client" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.client_instance_type
  key_name               = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.nomad_ui_ingress.id, aws_security_group.ssh_ingress.id, aws_security_group.clients_ingress.id, aws_security_group.allow_all_internal.id]
  count                  = var.client_count

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.private_key.private_key_pem
    host        = self.public_ip
  }

  # NomadJoinTag is necessary for nodes to automatically join the cluster
  tags = merge(
    {
      "Name" = "${var.name}-client-${count.index}"
    },
    {
      "NomadJoinTag" = "auto-join"
    },
    {
      "NomadType" = "client"
    }
  )

  root_block_device {
    volume_type           = "gp2"
    volume_size           = var.root_block_device_size
    delete_on_termination = "true"
  }

  ebs_block_device {
    device_name           = "/dev/xvdd"
    volume_type           = "gp2"
    volume_size           = "50"
    delete_on_termination = "true"
  }

  provisioner "remote-exec" {
    inline = ["sudo mkdir -p /ops", "sudo chmod 777 -R /ops"]
  }

  provisioner "file" {
    source      = "../shared"
    destination = "/ops"
  }

  user_data = templatefile("../shared/data-scripts/user-data-client.sh", {
    region                    = var.region
    cloud_env                 = "aws"
    retry_join                = var.retry_join
    nomad_version             = var.nomad_version
  })
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

  metadata_options {
    http_endpoint          = "enabled"
    instance_metadata_tags = "enabled"
  }
}

resource "aws_iam_instance_profile" "instance_profile" {
  name_prefix = var.name
  role        = aws_iam_role.instance_role.name
}

resource "aws_iam_role" "instance_role" {
  name_prefix        = var.name
  assume_role_policy = data.aws_iam_policy_document.instance_role.json
}

data "aws_iam_policy_document" "instance_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "auto_discover_cluster" {
  name   = "${var.name}-auto-discover-cluster"
  role   = aws_iam_role.instance_role.id
  policy = data.aws_iam_policy_document.auto_discover_cluster.json
}

data "aws_iam_policy_document" "auto_discover_cluster" {
  statement {
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "autoscaling:DescribeAutoScalingGroups",
    ]

    resources = ["*"]
  }
}