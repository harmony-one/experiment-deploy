resource "null_resource" "provisioner" {
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

  depends_on = ["aws_spot_instance_request.foundation-node"]
}
