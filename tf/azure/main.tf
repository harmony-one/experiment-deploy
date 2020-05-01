provider "azurerm" {
  version = "=2.8.0"
  skip_provider_registration = true

  features {}
}

resource "random_id" "vm_id" {
  byte_length = 8
}

resource "azurerm_public_ip" "main" {
  name                = "node-${var.blskey_index}-${random_id.vm_id.hex}-ip"
  location            = var.node_location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "main" {
  name                = "node-${var.blskey_index}-${random_id.vm_id.hex}-nic"
  location            = var.node_location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "default"
    subnet_id                     = var.sub_net
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

resource "azurerm_virtual_machine" "main" {
  name                  = "node-${var.blskey_index}-${random_id.vm_id.hex}"
  location              = var.node_location
  resource_group_name   = var.resource_group_name
  network_interface_ids = [azurerm_network_interface.main.id]
  vm_size               = var.vm_size

  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.7"
    version   = "latest"
  }

  storage_os_disk {
    name              = "noed-${var.blskey_index}-${random_id.vm_id.hex}-os-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "node-${var.blskey_index}-${random_id.vm_id.hex}"
    admin_username = "hmy"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = file(var.ssh_public_key_path)
      path     = "/home/hmy/.ssh/authorized_keys"
    }
  }

  // TODO
  # provisioner "local-exec" {
  #   command = "aws s3 cp s3://harmony-secret-keys/bls/${lookup(var.harmony_nodes_blskeys, var.blskey_index, var.default_key)}.key files/bls.key"
  # }

  provisioner "file" {
    source      = "files/bls.key"
    destination = "/home/hmy/bls.key"
    connection {
      host        = azurerm_public_ip.main.ip_address
      type        = "ssh"
      user        = "hmy"
      private_key = file(var.ssh_private_key_path)
      timeout     = "1m"
    }
  }

  // TODO
  provisioner "file" {
    source      = "files/bls.pass"
    destination = "/home/hmy/bls.pass"
    connection {
      host        = azurerm_public_ip.main.ip_address
      type        = "ssh"
      user        = "hmy"
      private_key = file(var.ssh_private_key_path)
      timeout     = "1m"
    }
  }

  provisioner "file" {
    source      = "files/harmony.service"
    destination = "/home/hmy/harmony.service"
    connection {
      host        = azurerm_public_ip.main.ip_address
      type        = "ssh"
      user        = "hmy"
      private_key = file(var.ssh_private_key_path)
      timeout     = "1m"
    }
  }

  provisioner "file" {
    source      = "files/node_exporter.service"
    destination = "/home/hmy/node_exporter.service"
    connection {
      host        = azurerm_public_ip.main.ip_address
      type        = "ssh"
      user        = "hmy"
      private_key = file(var.ssh_private_key_path)
      timeout     = "1m"
    }
  }

  provisioner "file" {
    source      = "files/rclone.sh"
    destination = "/home/hmy/rclone.sh"
    connection {
      host        = azurerm_public_ip.main.ip_address
      type        = "ssh"
      user        = "hmy"
      private_key = file(var.ssh_private_key_path)
      timeout     = "1m"
    }
  }

  provisioner "file" {
    source      = "files/rclone.conf"
    destination = "/home/hmy/rclone.conf"
    connection {
      host        = azurerm_public_ip.main.ip_address
      type        = "ssh"
      user        = "hmy"
      private_key = file(var.ssh_private_key_path)
      timeout     = "1m"
    }
  }

  provisioner "file" {
    source      = "files/uploadlog.sh"
    destination = "/home/hmy/uploadlog.sh"
    connection {
      host        = azurerm_public_ip.main.ip_address
      type        = "ssh"
      user        = "hmy"
      private_key = file(var.ssh_private_key_path)
      timeout     = "1m"
    }
  }

  provisioner "file" {
    source      = "files/crontab"
    destination = "/home/hmy/crontab"
    connection {
      host        = azurerm_public_ip.main.ip_address
      type        = "ssh"
      user        = "hmy"
      private_key = file(var.ssh_private_key_path)
      timeout     = "1m"
    }
  }

  provisioner "file" {
    source      = "files/userdata.sh"
    destination = "/home/hmy/userdata.sh"
    connection {
      host        = azurerm_public_ip.main.ip_address
      type        = "ssh"
      user        = "hmy"
      private_key = file(var.ssh_private_key_path)
      timeout     = "1m"
    }
  }

  provisioner "file" {
    source      = "files/reboot.sh"
    destination = "/home/hmy/reboot.sh"
    connection {
      host        = azurerm_public_ip.main.ip_address
      type        = "ssh"
      user        = "hmy"
      private_key = file(var.ssh_private_key_path)
      timeout     = "1m"
    }
  }

  # provisioner "remote-exec" {
  #   inline = [
  #     "sudo setenforce 0",
  #     "sudo sed -i /etc/selinux/config -r -e 's/^SELINUX=.*/SELINUX=disabled/g'",
  #     "sudo yum install -y epel-release",
  #     "sudo yum install -y bind-utils jq psmisc unzip",
  #     "curl -LO https://harmony.one/node.sh",
  #     "chmod +x node.sh rclone.sh uploadlog.sh",
  #     "mkdir -p /home/hmy/.config/rclone",
  #     "mkdir -p /home/hmy/.hmy/blskeys",
  #     "mv -f /home/hmy/*.key /home/hmy/.hmy/blskeys",
  #     "mv -f rclone.conf /home/hmy/.config/rclone",
  #     "crontab crontab",
  #     "/home/hmy/node.sh -I -d && cp -f /home/hmy/staging/harmony /home/hmy",
  #     "sudo cp -f harmony.service /etc/systemd/system/harmony.service",
  #     "sudo ./node_exporter.sh",
  #     "sudo systemctl daemon-reload",
  #     "sudo systemctl start node_exporter",
  #     "sudo systemctl enable node_exporter",
  #     "sudo systemctl enable harmony.service",
  #     "curl https://rclone.org/install.sh | sudo bash",
  #     "echo ${var.blskey_index} > index.txt",
  #     "echo ${var.default_shard} > shard.txt",
  #     "mkdir -p harmony_db_0; mkdir -p harmony_db_${var.default_shard}",
  #   ]
  #   connection {
  #     host        = azurerm_public_ip.main.ip_address
  #     type        = "ssh"
  #     user        = "hmy"
  #     private_key = file(var.ssh_private_key_path)
  #     timeout     = "1m"
  #   }
  # }
}