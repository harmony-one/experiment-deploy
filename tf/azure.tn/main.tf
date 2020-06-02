provider "azurerm" {
  version = "=2.8.0"
  skip_provider_registration = true

  features {}
}

data "azurerm_subnet" "testnet" {
  name                 = "subnet"
  virtual_network_name = "${var.network}-${var.location}-vn"
  resource_group_name  = "${var.network}-${var.location}"
}

resource "azurerm_public_ip" "testnet" {
  count               = var.vm_count
  name                = "${var.type}-node-${count.index}-ip"
  location            = var.location
  resource_group_name = "${var.network}-${var.location}"
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "testnet" {
  count               = var.vm_count
  name                = "${var.type}-node-${count.index}-nic"
  location            = var.location
  resource_group_name = "${var.network}-${var.location}"

  ip_configuration {
    name                          = "default"
    subnet_id                     = data.azurerm_subnet.testnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = element(azurerm_public_ip.testnet.*.id, count.index)
  }
}

resource "azurerm_virtual_machine" "testnet" {
  count                 = var.vm_count
  name                  = "${var.type}-node-${count.index}"
  location              = var.location
  resource_group_name   = "${var.network}-${var.location}"
  network_interface_ids = [element(azurerm_network_interface.testnet.*.id, count.index)]
  vm_size               = var.vm_size

  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "8_1"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${var.type}-node-${count.index}-os-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "${var.type}-node-${count.index}"
    admin_username = "hmy"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = file(var.ssh_public_key_path)
      path     = "/home/hmy/.ssh/authorized_keys"
    }
  }
}
