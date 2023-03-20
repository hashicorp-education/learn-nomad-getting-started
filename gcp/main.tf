terraform {
  required_version = ">= 0.12"
}

locals {
  retry_join = "provider=gce project_name=${var.project} tag_value=auto-join"
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

resource "google_compute_network" "hashistack" {
  name = "hashistack-${var.name}"
}

resource "google_compute_firewall" "nomad_ui_ingress" {
  name          = "${var.name}-ui-ingress"
  network       = google_compute_network.hashistack.name
  source_ranges = [var.allowlist_ip]

  # Nomad
  allow {
    protocol = "tcp"
    ports    = [4646]
  }
}

resource "google_compute_firewall" "ssh_ingress" {
  name          = "${var.name}-ssh-ingress"
  network       = google_compute_network.hashistack.name
  source_ranges = [var.allowlist_ip]

  # SSH
  allow {
    protocol = "tcp"
    ports    = [22]
  }
}

resource "google_compute_firewall" "allow_all_internal" {
  name        = "${var.name}-allow-all-internal"
  network     = google_compute_network.hashistack.name
  source_tags = ["auto-join"]

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
}

resource "google_compute_firewall" "clients_ingress" {
  name          = "${var.name}-clients-ingress"
  network       = google_compute_network.hashistack.name
  source_ranges = [var.allowlist_ip]
  target_tags   = ["nomad-clients"]

  # Add application ingress rules here
  # These rules are applied only to the client nodes

  # example app on port 5000, replace with your application port
  allow {
    protocol = "tcp"
    ports    = [5000]
  }
}

data "google_compute_image" "ubuntu-1604" {
  family  = "ubuntu-pro-1604-lts"
  project = "ubuntu-os-pro-cloud"
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Uncomment the private key resource below if you want to SSH to any of the instances
# Run init and apply again after uncommenting:
# terraform init && terraform apply
# Then SSH with the tf-key.pem file:
# ssh -i tf-key.pem ubuntu@INSTANCE_PUBLIC_IP

# resource "local_file" "tf_pem" {
#   filename = "${path.module}/tf-key.pem"
#   content = tls_private_key.private_key.private_key_pem
#   file_permission = "0400"
# }

resource "google_compute_instance" "server" {
  count        = var.server_count
  name         = "${var.name}-server-${count.index}"
  machine_type = var.server_instance_type
  zone         = var.zone
  tags         = ["auto-join"]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.private_key.private_key_pem
    host        = self.network_interface.0.access_config.0.nat_ip
  }

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu-1604.self_link
      size  = var.root_block_device_size
    }
  }

  network_interface {
    network = google_compute_network.hashistack.name
    access_config {
      // Leave empty to get an ephemeral public IP
    }
  }

  service_account {
    # https://developers.google.com/identity/protocols/googlescopes
    scopes = [
      "https://www.googleapis.com/auth/compute.readonly",
      "https://www.googleapis.com/auth/logging.write",
    ]
  }

  metadata = {
    ssh-keys = "ubuntu:${tls_private_key.private_key.public_key_openssh}"
  }

  provisioner "remote-exec" {
    inline = ["sudo mkdir -p /ops", "sudo chmod 777 -R /ops"]
  }

  provisioner "file" {
    source      = "../shared"
    destination = "/ops"
  }

  metadata_startup_script = templatefile("../shared/data-scripts/user-data-server.sh", {
    server_count              = var.server_count
    region                    = var.region
    cloud_env                 = "gce"
    retry_join                = local.retry_join
    nomad_version             = var.nomad_version
  })
}

resource "google_compute_instance" "client" {
  count        = var.client_count
  name         = "${var.name}-client-${count.index}"
  machine_type = var.client_instance_type
  zone         = var.zone
  tags         = ["auto-join", "nomad-clients"]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.private_key.private_key_pem
    host        = self.network_interface.0.access_config.0.nat_ip
  }

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu-1604.self_link
      size  = var.root_block_device_size
    }
  }

  network_interface {
    network = google_compute_network.hashistack.name
    access_config {
      // Leave empty to get an ephemeral public IP
    }
  }

  service_account {
    # https://developers.google.com/identity/protocols/googlescopes
    scopes = [
      "https://www.googleapis.com/auth/compute.readonly",
      "https://www.googleapis.com/auth/logging.write",
    ]
  }

  metadata = {
    ssh-keys = "ubuntu:${tls_private_key.private_key.public_key_openssh}"
  }

  provisioner "remote-exec" {
    inline = ["sudo mkdir -p /ops", "sudo chmod 777 -R /ops"]
  }

  provisioner "file" {
    source      = "../shared"
    destination = "/ops"
  }

  metadata_startup_script = templatefile("../shared/data-scripts/user-data-client.sh", {
    region                    = var.region
    cloud_env                 = "gce"
    retry_join                = local.retry_join
    nomad_version             = var.nomad_version
  })
}