// set a different cloud credentials
// export GOOGLE_CLOUD_KEYFILE_JSON=benchmark-209420-a7a77ae89c9c.json

provider "google" {
  //  credentials = "${file("benchmark-209420-a7a77ae89c9c.json")}"
  //  region  = "${var.region}"
  project = "benchmark-209420"
  version = "~> 2.20"
}

// Terraform plugin for creating random ids
resource "random_id" "instance_id" {
  byte_length = 8
}

// A single Google Cloud Engine instance
resource "google_compute_instance" "fn" {
  name         = "node-s${var.shard}-${var.blskey_indexes}"
  machine_type = "${var.node_instance_type}"
  zone         = "${var.zone}"

  boot_disk {
    initialize_params {
      image = "centos-cloud/centos-8"
      size  = "${var.node_volume_size}"
    }
  }

  metadata_startup_script = "sudo yum update -y; sudo yum install -y bind-utils jq psmisc dnsutils;"

  network_interface {
    network = "${var.vpc_name}"

    access_config {
      // Include this section to give the VM an external ip address
    }
  }

  provisioner "file" {
    source      = "files/blskeys"
    destination = "/home/gce-user/.hmy"
    connection {
      host  = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
      type  = "ssh"
      user  = "gce-user"
      agent = true
    }
  }

  provisioner "file" {
    source      = "files/bls.pass"
    destination = "/home/gce-user/bls.pass"
    connection {
      host  = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
      type  = "ssh"
      user  = "gce-user"
      agent = true
    }
  }

  provisioner "file" {
    source      = "files/crontab"
    destination = "/home/gce-user/crontab"
    connection {
      host  = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
      type  = "ssh"
      user  = "gce-user"
      agent = true
    }
  }

  provisioner "file" {
    source      = "files/multikey.txt"
    destination = "/home/gce-user/multikey.txt"
    connection {
      host  = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
      type  = "ssh"
      user  = "gce-user"
      agent = true
    }
  }

  provisioner "file" {
    source      = "files/service/harmony.service"
    destination = "/home/gce-user/harmony.service"
    connection {
      host  = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
      type  = "ssh"
      user  = "gce-user"
      agent = true
    }
  }

  provisioner "file" {
    source      = "files/rclone.conf"
    destination = "/home/gce-user/rclone.conf"
    connection {
      host  = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
      type  = "ssh"
      user  = "gce-user"
      agent = true
    }
  }

  provisioner "file" {
    source      = "files/rclone.sh"
    destination = "/home/gce-user/rclone.sh"
    connection {
      host  = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
      type  = "ssh"
      user  = "gce-user"
      agent = true
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install -y bind-utils jq psmisc unzip",
      "curl -LO https://harmony.one/node.sh",
      "chmod +x node.sh rclone.sh",
      "mkdir -p /home/gce-user/.config/rclone /home/gce-user/.hmy/blskeys",
      "mv -f rclone.conf /home/gce-user/.config/rclone",
      "mv -f /home/gce-user/.hmy/*.key /home/gce-user/.hmy/blskeys",
      "/home/gce-user/node.sh -I -d && cp -f /home/gce-user/staging/harmony /home/gce-user",
      "sudo cp -f harmony.service /lib/systemd/system/harmony.service",
      "sudo systemctl enable harmony.service",
      "sudo systemctl daemon-reload",
      "crontab crontab",
      "curl https://rclone.org/install.sh | sudo bash",
      "echo ${var.shard} > shard.txt",
      "mkdir -p harmony_db_0; mkdir -p harmony_db_${var.shard}",
      "sudo setenforce 0",
    ]
    connection {
      host  = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
      type  = "ssh"
      user  = "gce-user"
      agent = true
    }

  }

  metadata = {
    ssh-keys = "gce-user:${file(var.public_key_path)}"
  }

}
