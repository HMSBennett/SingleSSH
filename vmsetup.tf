variable "prefix" {
	default = "SingleSSH"
}

provider "azurerm" {
	version = "=1.30.1"
}

resource "azurerm_resource_group" "main" {
	name = "${var.prefix}-Group"
	location = "uksouth"
}

resource "azurerm_virtual_network" "main" {
	name = "${var.prefix}-network"
	address_space = ["10.0.0.0/16"]
	location = "${azurerm_resource_group.main.location}"
	resource_group_name = "${azurerm_resource_group.main.name}"
}

resource "azurerm_subnet" "internal" {
	name = "internal"
	resource_group_name = "${azurerm_resource_group.main.name}"
	virtual_network_name = "${azurerm_virtual_network.main.name}"
	address_prefix = "10.0.2.0/24"
}

resource "azurerm_network_security_group" "main" {
	name = "${var.prefix}-NSG"
	location = "${azurerm_resource_group.main.location}"
	resource_group_name = "${azurerm_resource_group.main.name}"
}

resource "azurerm_network_security_rule" "main" {
	name = "SSH"
	priority = 100
	direction = "Outbound"
	access = "Allow"
	protocol = "Tcp"
	source_port_range = "*"
	destination_port_range = "22"
	source_address_prefix = "*"
	destination_address_prefix = "*"
	resource_group_name = "${azurerm_resource_group.main.name}"
	network_security_group_name = "${azurerm_network_security_group.main.name}"
}

resource "azurerm_public_ip" "main" {
	name = "${var.prefix}-IP"
	location = "${azurerm_resource_group.main.location}"
	resource_group_name = "${azurerm_resource_group.main.name}"
	allocation_method = "Static"
	domain_name_label = "hms-${formatdate("DDMMYYhhmmss",timestamp())}"

	tags = {
		environment = "Production"
	}
}

resource "azurerm_network_interface" "main" {
        name = "${var.prefix}-nic"
        location = "${azurerm_resource_group.main.location}"
        resource_group_name = "${azurerm_resource_group.main.name}"

        ip_configuration {
                name = "${var.prefix}-IP-Config"
                subnet_id = "${azurerm_subnet.internal.id}"
                private_ip_address_allocation = "Dynamic"
		public_ip_address_id = "${azurerm_public_ip.main.id}"
        }
}

resource "azurerm_virtual_machine" "main" {
	name = "${var.prefix}-vm"
	location = "${azurerm_resource_group.main.location}"
	resource_group_name = "${azurerm_resource_group.main.name}"
	network_interface_ids = ["${azurerm_network_interface.main.id}"]
	vm_size = "Standard_B1MS"

	storage_image_reference {
		publisher = "Canonical"
		offer = "UbuntuServer"
		sku = "16.04-LTS"
		version = "latest"
	}

	storage_os_disk {
		name = "myosdisk1"
		caching = "ReadWrite"
		create_option = "FromImage"
		managed_disk_type = "Standard_LRS"
	}

	os_profile {
		computer_name = "testmachine"
		admin_username = "hms"
		admin_password = "guffin123!"
	}

	os_profile_linux_config {
		disable_password_authentication = false
		
		ssh_keys {
			path = "/home/hms/.ssh/authorized_keys"
			key_data = "${file("~/.ssh/id_rsa.pub")} "
		}
	}

	tags = {
		environment = "staging"	
	}
	
	provisioner "remote-exec" {
		inline = [
			"git clone https://github.com/HMSBennett/Jenkins",
			"cd Jenkins",
			"./jenkinsInstall.sh",
			]
		connection{
			type = "ssh"
			user = "hms"
			private_key = file("/home/hms/.ssh/id_rsa")
			host = "${azurerm_public_ip.main.fqdn}"
		}
	}
}
