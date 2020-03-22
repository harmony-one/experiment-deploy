provider "aws" {
  region                  = var.aws_region
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "mainnet"
}

resource "aws_spot_instance_request" "foundation-node" {
  ami                             = "${data.aws_ami.harmony-node-ami.id}"
  spot_price                      = "${var.spot_instance_price}"
  instance_type                   = "${var.node_instance_type}"
  vpc_security_group_ids          = ["${lookup(var.security_groups, var.aws_region, var.default_key)}"]
  key_name                        = "harmony-node"
  wait_for_fulfillment            = true
  user_data                       = "${file(var.user_data)}"
  spot_type                       = "${var.spot_type}"
  instance_interruption_behaviour = "${var.instance_interruption_behaviour}"

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "${var.node_volume_size}"
    delete_on_termination = false
  }

  tags = {
    Name    = "HarmonyNode-MainNet"
    Project = "Harmony"
  }

  volume_tags = {
    Name    = "HarmonyNode-MainNet-Volume"
    Project = "Harmony"
  }

  provisioner "local-exec" {
    command = "aws s3 cp s3://harmony-secret-keys/bls/${lookup(var.harmony-nodes-blskeys, var.blskey_index, var.default_key)}.key files/bls.key"
  }

  provisioner "file" {
    source      = "files/bls.key"
    destination = "/home/ec2-user/bls.key"
    connection {
      host        = "${aws_spot_instance_request.foundation-node.public_ip}"
      type        = "ssh"
      user        = "ec2-user"
      agent       = true
    }
  }

  provisioner "file" {
    source      = "files/blskeys"
    destination = "/home/ec2-user/.hmy"
    connection {
      host        = "${aws_spot_instance_request.foundation-node.public_ip}"
      type        = "ssh"
      user        = "ec2-user"
      agent       = true
    }
  }

  provisioner "file" {
    source      = "files/bls.pass"
    destination = "/home/ec2-user/bls.pass"
    connection {
      host        = "${aws_spot_instance_request.foundation-node.public_ip}"
      type        = "ssh"
      user        = "ec2-user"
      agent       = true
    }
  }

  provisioner "file" {
    source      = "files/service/harmony.service"
    destination = "/home/ec2-user/harmony.service"
    connection {
      host        = "${aws_spot_instance_request.foundation-node.public_ip}"
      type        = "ssh"
      user        = "ec2-user"
      agent       = true
    }
  }

  provisioner "file" {
    source      = "files/node_exporter.service"
    destination = "/home/ec2-user/node_exporter.service"
    connection {
      host        = "${aws_spot_instance_request.foundation-node.public_ip}"
      type        = "ssh"
      user        = "ec2-user"
      agent       = true
    }
  }

  provisioner "file" {
    source      = "files/rclone.conf"
    destination = "/home/ec2-user/rclone.conf"
    connection {
      host        = "${aws_spot_instance_request.foundation-node.public_ip}"
      type        = "ssh"
      user        = "ec2-user"
      agent       = true
    }
  }

  provisioner "file" {
    source      = "files/rclone.sh"
    destination = "/home/ec2-user/rclone.sh"
    connection {
      host        = "${aws_spot_instance_request.foundation-node.public_ip}"
      type        = "ssh"
      user        = "ec2-user"
      agent       = true
    }
  }

  provisioner "file" {
    source      = "files/uploadlog.sh"
    destination = "/home/ec2-user/uploadlog.sh"
    connection {
      host        = "${aws_spot_instance_request.foundation-node.public_ip}"
      type        = "ssh"
      user        = "ec2-user"
      agent       = true
    }
  }

  provisioner "file" {
    source      = "files/crontab"
    destination = "/home/ec2-user/crontab"
    connection {
      host        = "${aws_spot_instance_request.foundation-node.public_ip}"
      type        = "ssh"
      user        = "ec2-user"
      agent       = true
    }
  }

  provisioner "file" {
    source      = "files/multikey.txt"
    destination = "/home/ec2-user/multikey.txt"
    connection {
      host        = "${aws_spot_instance_request.foundation-node.public_ip}"
      type        = "ssh"
      user        = "ec2-user"
      agent       = true
    }
  }

  provisioner "remote-exec" {
    inline = [
      "curl -LO https://harmony.one/node.sh",
      "chmod +x node.sh rclone.sh uploadlog.sh",
      "mkdir -p /home/ec2-user/.config/rclone",
      "mkdir -p /home/ec2-user/.hmy/blskeys",
      "mv -f /home/ec2-user/.hmy/*.key /home/ec2-user/.hmy/blskeys",
      "mv -f rclone.conf /home/ec2-user/.config/rclone",
      "crontab crontab",
      "/home/ec2-user/node.sh -I -d && cp -f /home/ec2-user/staging/harmony /home/ec2-user",
      "sudo cp -f harmony.service /etc/systemd/system/harmony.service",
      "sudo cp -f node_exporter.service /etc/systemd/system/node_exporter.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable harmony.service",
      "sudo systemctl enable node_exporter",
      "sudo systemctl start node_exporter",
      "echo ${var.blskey_index} > index.txt",
      "echo ${var.default_shard} > shard.txt",
      "mkdir harmony_db_0; mkdir harmony_db_${var.default_shard}",
    ]
    connection {
      host        = "${aws_spot_instance_request.foundation-node.public_ip}"
      type        = "ssh"
      user        = "ec2-user"
      agent       = true
    }
  }

}
