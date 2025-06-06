# Configure the Terraform runtime requirements.
terraform {
  required_version = ">= 1.1.0"

  required_providers {
    # Azure Resource Manager provider and version
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.3"
    }
  }
}

# Define providers and their config params
provider "azurerm" {
  # Leave the features block empty to accept all defaults
  features {}
}

provider "cloudinit" {
  # Configuration options
}

variable "labelPrefix" {
  type = string
  default = ""
}

variable "region" {
  description = "location of where the cloud is running"
  type    = string
  default = "westus2"
}

variable "admin_username" {
  type = string
  default = ""
}

resource "azurerm_resource_group" "rg" {
    name = "${var.labelPrefix}-A05-resource-group"
    location = var.region
}

resource "azurerm_public_ip" "webserver" {
    name  = "${var.labelPrefix}-public-ip"
    resource_group_name = azurerm_resource_group.rg.name
    location = azurerm_resource_group.rg.location
    allocation_method = "Dynamic"
}

resource "azurerm_virtual_network" "vnet" {
    name = "${var.labelPrefix}-virtual-network"
    resource_group_name = azurerm_resource_group.rg.name
    location = azurerm_resource_group.rg.location
    address_space = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "webserver" {
    name = "${var.labelPrefix}-subnet"
    resource_group_name = var.azurerm_resource_group.rg.name
    virtual_network_name = var.azurerm_virtual_network.vnet.name
    address_prefixixes = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "webserver" {
  name                = "${var.labelPrefix}-Security-Group"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "ssh"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "http"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "vnic" {
    name                = "${var.labelPrefix}-network-interface-card"
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name

    ip_configuration {
        name                          = "${var.labelPrefix}-Configuration"
        subnet_id                     = azurerm_virtual_network.subnet.name
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.ip
    }

}

resource "azurerm_network_interface_security_group_association" "webserver" {
    network_interface_id = azurerm_network_interface.webserver.subnet_id
    azurerm_network_security_group_id = azurerm_network_security_group.subnet_id
}

data "cloudinit_config" "init" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content = file("${path.module}/init.sh")
    filename = "init.sh"
  }
}

resource "azurerm_virtual_machine" "vm" {
  name                        = "${var.labelPrefix}-virtual_machine"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = azurerm_resource_group.rg.location
  network_interface_id        = [azurerm_network_interface.webserver.id]
  size                        = "Standard_B1s"
  
  instances                   = 1
  platform_fault_domain_count = 1     # For zonal deployments, this must be set to 1
  zones                       = ["1"] # Zones required to lookup zone in the startup script

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("~/.ssh/id_rsa.pub")    
  }
  
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-LTS-gen2"
    version   = "latest"
  }
  
  os_disk {
    name                 = "${var.labelPrefix}-disk"
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  computer_name                  = "${var.labelPrefix}-virtual_machine"
  admin_username                 = var.admin_username
  disable_password_authetication = true

  custom_data = data.cloudinit_config.init.rendered
}

output "resource_group_name" {
    value = resource_group.rg.name
}

output "public_ip" {
    value = azurerm_virtual_machine.vm.public_ip_address
}

