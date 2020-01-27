provider "digitalocean" {
    token = var.do_token
}

resource "random_id" "droplet_id" {
    byte_length = 8
}

resource "digitalocean_droplet" "harmony_node" {
    name        = "node-s${var.shard}-${var.blskey_index}-${random_id.droplet_id.hex}"
    image       = var.droplet_system_image
    region      = var.droplet_region
    size        = var.droplet_size
    tags        = ["harmony"]
    # ssh_keys    = [digitalocean_ssh_key.harmony_ssh_key.fingerprint]
    ssh_keys = [25624276]
    volume_ids  = [digitalocean_volume.harmony_data_volume.id]
    resize_disk = "false"
    depends_on = [digitalocean_volume.harmony_data_volume]


    # provisioner "local-exec" {
    #     command = "aws s3 cp s3://harmony-secret-keys/bls/${lookup(var.harmony-nodes-blskeys, var.blskey_index, var.default_key)}.key files/bls.key"
    # }

    # provisioner "file" {
    #     source      = "files/bls.key"
    #     destination = "/home/ec2-user/bls.key"
    #     connection {
    #     host        = "${aws_spot_instance_request.foundation-node.public_ip}"
    #     type        = "ssh"
    #     user        = "ec2-user"
    #     private_key = "${file(var.private_key_path)}"
    #     agent       = true
    #     }
    # }

    # provisioner "file" {
    #     source      = "files/bls.pass"
    #     destination = "/home/ec2-user/bls.pass"
    #     connection {
    #     host        = "${aws_spot_instance_request.foundation-node.public_ip}"
    #     type        = "ssh"
    #     user        = "ec2-user"
    #     private_key = "${file(var.private_key_path)}"
    #     agent       = true
    #     }
    # }

    # provisioner "file" {
    #     source      = "files/harmony.service"
    #     destination = "/home/ec2-user/harmony.service"
    #     connection {
    #     host        = "${aws_spot_instance_request.foundation-node.public_ip}"
    #     type        = "ssh"
    #     user        = "ec2-user"
    #     private_key = "${file(var.private_key_path)}"
    #     agent       = true
    #     }
    # }

    # provisioner "file" {
    #     source      = "files/node_exporter.service"
    #     destination = "/home/ec2-user/node_exporter.service"
    #     connection {
    #     host        = "${aws_spot_instance_request.foundation-node.public_ip}"
    #     type        = "ssh"
    #     user        = "ec2-user"
    #     private_key = "${file(var.private_key_path)}"
    #     agent       = true
    #     }
    # }

    # provisioner "file" {
    #     source      = "files/rclone.conf"
    #     destination = "/home/ec2-user/rclone.conf"
    #     connection {
    #     host        = "${aws_spot_instance_request.foundation-node.public_ip}"
    #     type        = "ssh"
    #     user        = "ec2-user"
    #     private_key = "${file(var.private_key_path)}"
    #     agent       = true
    #     }
    # }

    # provisioner "file" {
    #     source      = "files/fast.sh"
    #     destination = "/home/ec2-user/fast.sh"
    #     connection {
    #     host        = "${aws_spot_instance_request.foundation-node.public_ip}"
    #     type        = "ssh"
    #     user        = "ec2-user"
    #     private_key = "${file(var.private_key_path)}"
    #     agent       = true
    #     }
    # }

    # provisioner "file" {
    #     source      = "files/rclone.sh"
    #     destination = "/home/ec2-user/rclone.sh"
    #     connection {
    #     host        = "${aws_spot_instance_request.foundation-node.public_ip}"
    #     type        = "ssh"
    #     user        = "ec2-user"
    #     private_key = "${file(var.private_key_path)}"
    #     agent       = true
    #     }
    # }

    # provisioner "file" {
    #     source      = "files/uploadlog.sh"
    #     destination = "/home/ec2-user/uploadlog.sh"
    #     connection {
    #     host        = "${aws_spot_instance_request.foundation-node.public_ip}"
    #     type        = "ssh"
    #     user        = "ec2-user"
    #     private_key = "${file(var.private_key_path)}"
    #     agent       = true
    #     }
    # }

    # provisioner "file" {
    #     source      = "files/crontab"
    #     destination = "/home/ec2-user/crontab"
    #     connection {
    #     host        = "${aws_spot_instance_request.foundation-node.public_ip}"
    #     type        = "ssh"
    #     user        = "ec2-user"
    #     private_key = "${file(var.private_key_path)}"
    #     agent       = true
    #     }
    # }


    # provisioner "remote-exec" {
    #     inline = [
    #     "curl -LO https://harmony.one/node.sh",
    #     "chmod +x node.sh rclone.sh fast.sh uploadlog.sh",
    #     "crontab crontab",
    #     "mkdir -p /home/ec2-user/.config/rclone",
    #     "mv -f rclone.conf /home/ec2-user/.config/rclone",
    #     "sudo mv -f harmony.service /etc/systemd/system/harmony.service",
    #     "sudo systemctl enable harmony.service",
    #     "sudo systemctl start harmony.service",
    #     "sudo mv -f node_exporter.service /etc/systemd/system/node_exporter.service",
    #     "sudo systemctl daemon-reload",
    #     "sudo systemctl start node_exporter",
    #     "sudo systemctl enable node_exporter"
    #     "echo ${var.blskey_index} > index.txt",
    #     ]
    #     connection {
    #     host        = "${aws_spot_instance_request.foundation-node.public_ip}"
    #     type        = "ssh"
    #     user        = "ec2-user"
    #     private_key = "${file(var.private_key_path)}"
    #     agent       = true
    #     }
    # } 

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
        source_addresses = ["0.0.0.0/0", "::/0"]
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

# test on Andy's local env
# resource "digitalocean_ssh_key" "harmony_ssh_key" {
#   name       = "Harmony Pub Key"
#   public_key = file("/Users/bwu2/.ssh/id_rsa.pub")
# }