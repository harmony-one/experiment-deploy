// set a different cloud credentials
// export GOOGLE_CLOUD_KEYFILE_JSON=benchmark-209420-a7a77ae89c9c.json

provider "google" {
//  credentials = "${file("benchmark-209420-a7a77ae89c9c.json")}"
  project     = "benchmark-209420"
  region       = "${var.region}"
  version     = "~> 2.20"
}

// Terraform plugin for creating random ids
resource "random_id" "instance_id" {
  byte_length = 8
}

// A single Google Cloud Engine instance
resource "google_compute_instance" "fn" {
 name         = "node-${var.blskey_index}-${random_id.instance_id.hex}"
 machine_type = "${var.node_instance_type}"
 zone         = "${var.zone}"

 boot_disk {
   initialize_params {
     image = "centos-cloud/centos-8"
     size = "${var.node_volume_size}"
   }
 }


 metadata_startup_script = "sudo yum update -y; sudo yum install -y bind-utils jq psmisc dnsutils;"

 network_interface {
   network = "${var.vpc_name}"

   access_config {
     // Include this section to give the VM an external ip address
   }
 }

  provisioner "local-exec" {
    command = "aws s3 cp s3://harmony-secret-keys/bls/${lookup(var.harmony-nodes-blskeys, var.blskey_index, var.default_key)}.key files/bls.key"
  }

    provisioner "file" {
        source = "files/bls.key"
        destination = "/home/gce-user/bls.key"
        connection {
            host = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
            type = "ssh"
            user = "gce-user"
            private_key = "${file(var.private_key_path)}"
        }
    }


    provisioner "file" {
        source = "files/bls.pass"
        destination = "/home/gce-user/bls.pass"
        connection {
            host = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
            type = "ssh"
            user = "gce-user"
            private_key = "${file(var.private_key_path)}"
        }
    }

    provisioner "file" {
        source = "files/harmony.service"
        destination = "/home/gce-user/harmony.service"
        connection {
            host = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
            type = "ssh"
            user = "gce-user"
            private_key = "${file(var.private_key_path)}"
        }
    }

    provisioner "file" {
        source = "files/node_exporter.service"
        destination = "/home/gce-user/node_exporter.service"
        connection {
            host = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
            type = "ssh"
            user = "gce-user"
            private_key = "${file(var.private_key_path)}"
        }
    }

    provisioner "file" {
        source = "files/rclone.conf"
        destination = "/home/gce-user/rclone.conf"
        connection {
            host = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
            type = "ssh"
            user = "gce-user"
            private_key = "${file(var.private_key_path)}"
        }
    }

    provisioner "file" {
        source = "files/rclone.sh"
        destination = "/home/gce-user/rclone.sh"
        connection {
            host = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
            type = "ssh"
            user = "gce-user"
            private_key = "${file(var.private_key_path)}"
        }
    }

    provisioner "remote-exec" {
        inline = [
        "sudo yum install -y bind-utils jq psmisc unzip",
        "curl -LO https://harmony.one/node.sh",
        "chmod +x node.sh rclone.sh",
        "mkdir -p /home/gce-user/.config/rclone",
        "mv -f rclone.conf /home/gce-user/.config/rclone",
        "sudo cp -f harmony.service /lib/systemd/system/harmony.service",
        "sudo systemctl enable harmony.service",
        "sudo systemctl start harmony.service",
        "curl https://rclone.org/install.sh | sudo bash",
        "echo ${var.blskey_index} > index.txt",
        ]
        connection {
            host = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
            type = "ssh"
            user = "gce-user"
            private_key = "${file(var.private_key_path)}"
        }

    } 

metadata = {
   ssh-keys = "gce-user:${file(var.public_key_path)}"
 }

}
