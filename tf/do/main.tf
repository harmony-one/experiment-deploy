provider "digitalocean" {
    token = var.do_token
}

resource "random_id" "droplet_id" {
    byte_length = 8
}

# Create a new SSH key
resource "digitalocean_ssh_key" "default" {
    name       = "Harmony Pub SSH Key"
    public_key = file("keys/do-node.pub")
}

resource "digitalocean_droplet" "harmony_node" {
    name        = "node-${var.blskey_index}-${random_id.droplet_id.hex}"
    image       = var.droplet_system_image
    region      = var.droplet_region
    size        = var.droplet_size
    tags        = ["harmony"]
    ssh_keys    = [digitalocean_ssh_key.default.fingerprint] 
    volume_ids  = [digitalocean_volume.harmony_data_volume.id]
    resize_disk = "false"
    depends_on = [digitalocean_volume.harmony_data_volume]     

    provisioner "local-exec" {
        command = "aws s3 cp s3://harmony-secret-keys/bls/${lookup(var.harmony-nodes-blskeys, var.blskey_index, var.default_key)}.key files/bls.key"
    }

    provisioner "file" {
        source      = "files/bls.key"
        destination = "/root/bls.key"
        connection {
            host        = digitalocean_droplet.harmony_node.ipv4_address
            type        = "ssh"
            user        = "root"
            private_key = "${file(var.ssh_private_key_path)}"
            timeout     = "2m"
            agent       = true
        }
    }

    provisioner "file" {
        source      = "files/bls.pass"
        destination = "/root/bls.pass"
        connection {
            host        = digitalocean_droplet.harmony_node.ipv4_address
            type        = "ssh"
            user        = "root"
            private_key = "${file(var.ssh_private_key_path)}"
            timeout     = "2m"
            agent       = true
        }
    }

    provisioner "file" {
        source      = "files/harmony.service"
        destination = "/root/harmony.service"
        connection {
            host        = digitalocean_droplet.harmony_node.ipv4_address
            type        = "ssh"
            user        = "root"
            private_key = "${file(var.ssh_private_key_path)}"
            timeout     = "2m"
            agent       = true
        }
    }

    provisioner "file" {
        source      = "files/rclone.sh"
        destination = "/root/rclone.sh"
        connection {
            host        = digitalocean_droplet.harmony_node.ipv4_address
            type        = "ssh"
            user        = "root"
            private_key = "${file(var.ssh_private_key_path)}"
            timeout     = "2m"
            agent       = true
        }
    }

    provisioner "file" {
        source      = "files/rclone.conf"
        destination = "/root/rclone.conf"
        connection {
            host        = digitalocean_droplet.harmony_node.ipv4_address
            type        = "ssh"
            user        = "root"
            private_key = "${file(var.ssh_private_key_path)}"
            timeout     = "2m"
            agent       = true
        }
    }

    provisioner "file" {
        source      = "files/uploadlog.sh"
        destination = "/root/uploadlog.sh"
        connection {
            host        = digitalocean_droplet.harmony_node.ipv4_address
            type        = "ssh"
            user        = "root"
            private_key = "${file(var.ssh_private_key_path)}"
            timeout     = "2m"
            agent       = true
        }
    }

    provisioner "file" {
        source      = "files/crontab"
        destination = "/root/crontab"
        connection {
            host        = digitalocean_droplet.harmony_node.ipv4_address
            type        = "ssh"
            user        = "root"
            private_key = "${file(var.ssh_private_key_path)}"
            timeout     = "2m"
            agent       = true
        }
    }

    provisioner "file" {
        source      = "files/userdata.sh"
        destination = "/root/userdata.sh"
        connection {
            host        = digitalocean_droplet.harmony_node.ipv4_address
            type        = "ssh"
            user        = "root"
            private_key = "${file(var.ssh_private_key_path)}"
            timeout     = "2m"
            agent       = true
        }
    }

    provisioner "file" {
        source      = "files/reboot.sh"
        destination = "/root/reboot.sh"
        connection {
            host        = digitalocean_droplet.harmony_node.ipv4_address
            type        = "ssh"
            user        = "root"
            private_key = "${file(var.ssh_private_key_path)}"
            timeout     = "2m"
            agent       = true
        }
    }

    provisioner "remote-exec" {
        inline = [
            "sudo yum install -y bind-utils jq psmisc unzip",
            "curl https://rclone.org/install.sh | sudo bash",
            "curl -LO https://harmony.one/node.sh",
            "chmod +x node.sh rclone.sh uploadlog.sh reboot.sh",
            "crontab crontab",
            "mkdir -p /root/.config/rclone",
            "mv -f rclone.conf /root/.config/rclone",
            "sudo mv -f harmony.service /etc/systemd/system/harmony.service",
            "sudo systemctl enable harmony.service",
            "sudo systemctl start harmony.service",
            "echo ${var.blskey_index} > index.txt",
            "chmod +x userdata.sh; ./userdata.sh",
            "sudo sed -i /etc/selinux/config -r -e 's/^SELINUX=.*/SELINUX=disabled/g'",
        ]
        connection {
            host        = digitalocean_droplet.harmony_node.ipv4_address
            type        = "ssh"
            user        = "root"
            private_key = "${file(var.ssh_private_key_path)}"
            timeout     = "2m"
            agent       = true
        }
    } 

}

resource "digitalocean_firewall" "harmony_fw" {
    name = "harmony-fw"

    droplet_ids = [digitalocean_droplet.harmony_node.id]

    inbound_rule {
        protocol         = "tcp"
        port_range       = "22"
        source_addresses = ["35.160.64.190/0"]
    }

    inbound_rule {
        protocol         = "tcp"
        port_range       = "6000"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }

    inbound_rule {
        protocol         = "tcp"
        port_range       = "9000"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }

    inbound_rule {
        protocol         = "tcp"
        port_range       = "9500"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }

    inbound_rule {
        protocol         = "tcp"
        port_range       = "9800"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }

    inbound_rule {
        protocol         = "tcp"
        port_range       = "53"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }

    inbound_rule {
        protocol         = "udp"
        port_range       = "53"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }

    outbound_rule {
        protocol              = "tcp"
        port_range            = "all"
        destination_addresses = ["0.0.0.0/0", "::/0"]
    }

    outbound_rule {
        protocol              = "udp"
        port_range            = "all"
        destination_addresses = ["0.0.0.0/0", "::/0"]
    }

    outbound_rule {
        protocol              = "tcp"
        port_range            = "53"
        destination_addresses = ["0.0.0.0/0", "::/0"]
    }

    outbound_rule {
        protocol              = "udp"
        port_range            = "53"
        destination_addresses = ["0.0.0.0/0", "::/0"]
    }

}