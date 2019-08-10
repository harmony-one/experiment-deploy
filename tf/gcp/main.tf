// Configure the Google Cloud provider
// https://cloud.google.com/community/tutorials/getting-started-on-gcp-with-terraform
provider "google" {
  credentials = "${file("flowing-digit-248617-6d1dac5cb46e.json")}"
  project     = "flowing-digit-248617"
  region      = "us-west1"
}

// Terraform plugin for creating random ids
resource "random_id" "instance_id" {
  byte_length = 8
}

resource "google_compute_firewall" "default" {
   name    = "flask-app-firewall"
   network = "default"

   allow {
     protocol = "tcp"
     ports    = ["5000"]
   }

}

// A single Google Cloud Engine instance
resource "google_compute_instance" "default" {
 name         = "flask-vm-${random_id.instance_id.hex}"
 machine_type = "n1-standard-1"
 zone         = "us-west1-a"

 boot_disk {
   initialize_params {
     image = "debian-cloud/debian-9"
   }
 }


// Make sure flask is installed on all new instances for later steps
// https://stackoverflow.com/questions/36591653/how-do-i-use-the-file-provisioner-with-google-compute-instance-template
 metadata_startup_script = "sudo apt-get update; "

 network_interface {
   network = "default"

   access_config {
     // Include this section to give the VM an external ip address
   }
 }

    provisioner "file" {
        source = "files/bls.key"
        destination = "/home/gce-user/bls.key"
        connection {
            host = "${google_compute_instance.default.network_interface.0.access_config.0.nat_ip}"
            type = "ssh"
            user = "gce-user"
            private_key = "${file("~/.ssh/id_rsa")}"
        }
    }


    provisioner "file" {
        source = "files/bls.pass"
        destination = "/home/gce-user/bls.pass"
        connection {
            host = "${google_compute_instance.default.network_interface.0.access_config.0.nat_ip}"
            type = "ssh"
            user = "gce-user"
            private_key = "${file("~/.ssh/id_rsa")}"
        }
    }

    provisioner "file" {
        source = "files/harmony.service"
        destination = "/home/gce-user/harmony.service"
        connection {
            host = "${google_compute_instance.default.network_interface.0.access_config.0.nat_ip}"
            type = "ssh"
            user = "gce-user"
            private_key = "${file("~/.ssh/id_rsa")}"
        }
    }

    provisioner "remote-exec" {
        inline = [
        "sudo apt update",
        "sudo apt-get install -y psmisc",
        "sudo apt-get install -y dnsutils",
        "curl -LO https://harmony.one/node.sh",
        "chmod +x node.sh",
        "sudo mv -f harmony.service /etc/systemd/system/harmony.service",
        "sudo systemctl enable harmony.service",
        "sudo systemctl start harmony.service",
        ]
        connection {
            host = "${google_compute_instance.default.network_interface.0.access_config.0.nat_ip}"
            type = "ssh"
            user = "gce-user"
            private_key = "${file("~/.ssh/id_rsa")}"
        }

    } 

metadata = {
   ssh-keys = "gce-user:${file("~/.ssh/id_rsa.pub")}"
 }

}


// $ssh andy@34.83.252.76
