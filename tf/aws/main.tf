provider "aws" {
  region     =  var.aws_region
  shared_credentials_file = "~/.aws/credentials"
  profile    = "mainnet"
}

data "aws_ami" "harmony-node-ami" {
  most_recent      = true
  owners = ["amazon"]
  filter {
    name   = "name"
    values = ["*amzn2-ami-hvm-2.0*-x86_64*"]
  }
}

resource "aws_spot_instance_request" "foundation-node" {
  ami           = "${data.aws_ami.harmony-node-ami.id}"
  spot_price    = "${var.spot_instance_price}"
  spot_type     = "one-time"
  instance_type = "${var.node_instance_type}"
  vpc_security_group_ids = ["${aws_security_group.harmony-node-sg.id}"]
  key_name = "harmony-node"
  
  provisioner "file" {
    source = "bls.key"
    destination = "/home/ec2-user/bls.key"
    connection {
      host = self.public_ip
      type = "ssh"
      user = "ec2-user"
      private_key = "${file(var.private_key_path)}"
      agent = true
    }
  }

  provisioner "remote-exec" {
    inline = [
      "curl -LO https://harmony.one/node.sh",
      "chmod +x node.sh",
		"home/ec2-user/setup.sh",
    ]
    connection {
      host = self.public_ip
      type = "ssh"
      user = "ec2-user"
      private_key = "${file(var.private_key_path)}"
      agent = true
    }
  }

  root_block_device  {
    volume_type = "gp2"
    volume_size = "${var.node_volume_size}"
  }

  tags = {
    Name    = "HarmonyNode-MainNet-Spot"
    Owner   = "${var.node_owner}"
    Project = "Harmony"
  }

  volume_tags = {
    Name    = "HarmonyNode-MainNet-Volume"
    Project = "Harmony"
  }
}
