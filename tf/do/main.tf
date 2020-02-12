provider "digitalocean" {
    token = var.do_token
}

resource "random_id" "droplet_id" {
    byte_length = 8
}

# Create a new SSH key
resource "digitalocean_ssh_key" "default" {
    name       = "Harmony Pub SSH Key"
    # this needs to be updated on the devops instance
    public_key = file("/Users/bwu2/.ssh/id_rsa.pub")
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


    provisioner "remote-exec" {
        inline = [
            "mount /dev/sda /mnt",
            "mkdir -p /mnt/do-user",
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


    provisioner "local-exec" {
        command = "aws s3 cp s3://harmony-secret-keys/bls/${lookup(var.harmony-nodes-blskeys, var.blskey_index, var.default_key)}.key files/bls.key"
    }

    provisioner "file" {
        source      = "files/bls.key"
        destination = "/mnt/do-user/bls.key"
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
        destination = "/mnt/do-user/bls.pass"
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
        destination = "/mnt/do-user/harmony.service"
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
        source      = "files/node_exporter.service"
        destination = "/mnt/do-user/node_exporter.service"
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
        destination = "/mnt/do-user/rclone.conf"
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
        destination = "/mnt/do-user/rclone.sh"
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
        destination = "/mnt/do-user/uploadlog.sh"
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
        destination = "/mnt/do-user/crontab"
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
            "cd /mnt/do-user",
            "curl -LO https://harmony.one/node.sh",
            "chmod +x node.sh rclone.sh uploadlog.sh",
            "crontab crontab",
            "mkdir -p /mnt/do-user/.config/rclone",
            "mv -f rclone.conf /mnt/do-user/.config/rclone",
            "sudo mv -f harmony.service /etc/systemd/system/harmony.service",
            "sudo systemctl enable harmony.service",
            "sudo systemctl start harmony.service",
            "sudo mv -f node_exporter.service /etc/systemd/system/node_exporter.service",
            "sudo systemctl daemon-reload",
            "sudo systemctl start node_exporter",
            "sudo systemctl enable node_exporter",
            "echo ${var.blskey_index} > index.txt",
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

resource "digitalocean_volume" "harmony_data_volume" {
    region                  = var.droplet_region
    name                    = "volume-s${var.shard}-${var.blskey_index}-${random_id.droplet_id.hex}"
    size                    = var.addition_volume_size
    initial_filesystem_type = "ext4"
    description             = "the data volume of harmony foundational node"
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
        port_range       = "9000"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }

    inbound_rule {
        protocol         = "tcp"
        port_range       = "9800"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }

    inbound_rule {
        protocol         = "tcp"
        port_range       = "6000"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }

    inbound_rule {
        protocol         = "tcp"
        port_range       = "9500"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }
}