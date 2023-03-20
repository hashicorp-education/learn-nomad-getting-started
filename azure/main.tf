terraform {
  required_version = ">= 0.12"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

locals {
  retry_join = "provider=azure tag_name=NomadJoinTag tag_value=auto-join subscription_id=${var.subscription_id} tenant_id=${var.tenant_id} client_id=${var.client_id} secret_access_key=${var.client_secret}"
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  client_id = var.client_id
  client_secret = var.client_secret
  tenant_id = var.tenant_id
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

resource "azurerm_resource_group" "hashistack" {
  name     = "hashistack"
  location = var.location
}

resource "azurerm_virtual_network" "hashistack-vn" {
  name                = "hashistack-vn"
  address_space       = ["10.0.0.0/16"]
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.hashistack.name}"
}

resource "azurerm_subnet" "hashistack-sn" {
  name                 = "hashistack-sn"
  resource_group_name  = "${azurerm_resource_group.hashistack.name}"
  virtual_network_name = "${azurerm_virtual_network.hashistack-vn.name}"
  address_prefixes       = ["10.0.2.0/24"]
}

resource "azurerm_network_security_group" "hashistack-sg" {
  name                = "hashistack-sg"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.hashistack.name}"
}

resource "azurerm_subnet_network_security_group_association" "hashistack-sg-association" {
  subnet_id                 = azurerm_subnet.hashistack-sn.id
  network_security_group_id = azurerm_network_security_group.hashistack-sg.id
}

resource "azurerm_network_security_rule" "nomad_ui_ingress" {
  name                        = "${var.name}-nomad-ui-ingress"
  resource_group_name         = "${azurerm_resource_group.hashistack.name}"
  network_security_group_name = "${azurerm_network_security_group.hashistack-sg.name}"

  priority  = 101
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_address_prefix      = var.allowlist_ip
  source_port_range          = "*"
  destination_port_range     = "4646"
  destination_address_prefix = "*"
}

resource "azurerm_network_security_rule" "ssh_ingress" {
  name                        = "${var.name}-ssh-ingress"
  resource_group_name         = "${azurerm_resource_group.hashistack.name}"
  network_security_group_name = "${azurerm_network_security_group.hashistack-sg.name}"

  priority  = 100
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_address_prefix      = var.allowlist_ip
  source_port_range          = "*"
  destination_port_range     = "22"
  destination_address_prefix = "*"
}

resource "azurerm_network_security_rule" "allow_all_internal" {
  name                        = "${var.name}-allow-all-internal"
  resource_group_name         = "${azurerm_resource_group.hashistack.name}"
  network_security_group_name = "${azurerm_network_security_group.hashistack-sg.name}"

  priority  = 103
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_address_prefix      = azurerm_subnet.hashistack-sn.address_prefixes[0]
  source_port_range          = "*"
  destination_port_range     = "*"
  destination_address_prefix = azurerm_subnet.hashistack-sn.address_prefixes[0]
}

resource "azurerm_network_security_rule" "clients_ingress" {
  name                        = "${var.name}-clients-ingress"
  resource_group_name         = "${azurerm_resource_group.hashistack.name}"
  network_security_group_name = "${azurerm_network_security_group.hashistack-sg.name}"

  priority  = 110
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  # Add application ingress rules here
  # These rules are applied only to the client nodes

  # example; replace with your application port
  source_address_prefix      = var.allowlist_ip
  source_port_range          = "*"
  destination_port_range     = "5000"
  destination_address_prefixes = azurerm_linux_virtual_machine.client[*].private_ip_address
}

resource "azurerm_public_ip" "hashistack-server-public-ip" {
  count                        = "${var.server_count}"
  name                         = "hashistack-server-ip-${count.index}"
  location                     = "${var.location}"
  resource_group_name          = "${azurerm_resource_group.hashistack.name}"
  allocation_method            = "Static"
}

resource "azurerm_network_interface" "hashistack-server-ni" {
  count                     = "${var.server_count}"
  name                      = "hashistack-server-ni-${count.index}"
  location                  = "${var.location}"
  resource_group_name       = "${azurerm_resource_group.hashistack.name}"

  ip_configuration {
    name                          = "hashistack-ipc"
    subnet_id                     = "${azurerm_subnet.hashistack-sn.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.hashistack-server-public-ip.*.id, count.index)}"
  }

  tags                            = {"NomadJoinTag" = "auto-join"}
}

resource "azurerm_linux_virtual_machine" "server" {
  name                  = "hashistack-server-${count.index}"
  location              = "${var.location}"
  resource_group_name   = "${azurerm_resource_group.hashistack.name}"
  network_interface_ids = ["${element(azurerm_network_interface.hashistack-server-ni.*.id, count.index)}"]
  size                  = "${var.server_instance_type}"
  count                 = "${var.server_count}"

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  os_disk {
    name              = "hashistack-server-osdisk-${count.index}"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  admin_ssh_key {
    username   = "ubuntu"
    public_key = tls_private_key.private_key.public_key_openssh
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.private_key.private_key_pem
    host        = self.public_ip_address
  }

  provisioner "remote-exec" {
    inline = ["sudo mkdir -p /ops", "sudo chmod 777 -R /ops"]
  }

  provisioner "file" {
    source      = "../shared"
    destination = "/ops"
  }

  computer_name  = "hashistack-server-${count.index}"
  admin_username = "ubuntu"
  custom_data    = "${base64encode(templatefile("../shared/data-scripts/user-data-server.sh", {
      region                    = var.location
      cloud_env                 = "azure"
      server_count              = "${var.server_count}"
      retry_join                = local.retry_join
      nomad_version             = var.nomad_version
  }))}"
}

resource "azurerm_public_ip" "hashistack-client-public-ip" {
  count                        = "${var.client_count}"
  name                         = "hashistack-client-ip-${count.index}"
  location                     = "${var.location}"
  resource_group_name          = "${azurerm_resource_group.hashistack.name}"
  allocation_method             = "Static"
}

resource "azurerm_network_interface" "hashistack-client-ni" {
  count                     = "${var.client_count}"
  name                      = "hashistack-client-ni-${count.index}"
  location                  = "${var.location}"
  resource_group_name       = "${azurerm_resource_group.hashistack.name}"

  ip_configuration {
    name                          = "hashistack-ipc"
    subnet_id                     = "${azurerm_subnet.hashistack-sn.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.hashistack-client-public-ip.*.id, count.index)}"
  }

  tags                            = {"NomadJoinTag" = "auto-join"}
}

resource "azurerm_linux_virtual_machine" "client" {
  name                  = "hashistack-client-${count.index}"
  location              = "${var.location}"
  resource_group_name   = "${azurerm_resource_group.hashistack.name}"
  network_interface_ids = ["${element(azurerm_network_interface.hashistack-client-ni.*.id, count.index)}"]
  size                  = "${var.client_instance_type}"
  count                 = "${var.client_count}"

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  os_disk {
    name              = "hashistack-client-osdisk-${count.index}"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  admin_ssh_key {
    username   = "ubuntu"
    public_key = tls_private_key.private_key.public_key_openssh
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.private_key.private_key_pem
    host        = self.public_ip_address
  }

  provisioner "remote-exec" {
    inline = ["sudo mkdir -p /ops", "sudo chmod 777 -R /ops"]
  }

  provisioner "file" {
    source      = "../shared"
    destination = "/ops"
  }

  computer_name  = "hashistack-client-${count.index}"
  admin_username = "ubuntu"
  custom_data    = "${base64encode(templatefile("../shared/data-scripts/user-data-client.sh", {
      region                    = var.location
      cloud_env                 = "azure"
      retry_join                = local.retry_join
      nomad_version             = var.nomad_version
  }))}"
}