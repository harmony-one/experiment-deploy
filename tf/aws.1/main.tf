provider "aws" {
  region                  = var.aws_region
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "mainnet"
}

resource "aws_spot_instance_request" "foundation-node" {
  ami                    = "${data.aws_ami.harmony-node-ami.id}"
  spot_price             = "${var.spot_instance_price}"
  spot_type              = "one-time"
  instance_type          = "${var.node_instance_type}"
  vpc_security_group_ids = ["${lookup(var.security_groups, var.aws_region, var.default_key)}"]
  key_name               = "harmony-node"
  wait_for_fulfillment   = true
  user_data              = "${file(var.user_data)}"

  root_block_device {
    volume_type = "gp2"
    volume_size = "${var.node_volume_size}"
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
      private_key = "${file(var.private_key_path)}"
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
      private_key = "${file(var.private_key_path)}"
      agent       = true
    }
  }

  provisioner "file" {
    source      = "files/harmony.service"
    destination = "/home/ec2-user/harmony.service"
    connection {
      host        = "${aws_spot_instance_request.foundation-node.public_ip}"
      type        = "ssh"
      user        = "ec2-user"
      private_key = "${file(var.private_key_path)}"
      agent       = true
    }
  }

  provisioner "file" {
    source      = "files/fast.sh"
    destination = "/home/ec2-user/fast.sh"
    connection {
      host        = "${aws_spot_instance_request.foundation-node.public_ip}"
      type        = "ssh"
      user        = "ec2-user"
      private_key = "${file(var.private_key_path)}"
      agent       = true
    }
  }


  provisioner "remote-exec" {
    inline = [
      "curl -LO https://harmony.one/node.sh",
      "chmod +x node.sh",
      "sudo mv -f harmony.service /etc/systemd/system/harmony.service",
      "sudo systemctl enable harmony.service",
      "sudo systemctl start harmony.service",
    ]
    connection {
      host        = "${aws_spot_instance_request.foundation-node.public_ip}"
      type        = "ssh"
      user        = "ec2-user"
      private_key = "${file(var.private_key_path)}"
      agent       = true
    }
  }

}
