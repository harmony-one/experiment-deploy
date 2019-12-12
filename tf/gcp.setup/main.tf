provider "google" {
  project = "benchmark-209420"
  version = "~> 2.20"
}

resource "google_compute_network" "vpc" {
  name                    = "${format("%s", "${var.company}-${var.env}-vpc")}"
  auto_create_subnetworks = "true"
  routing_mode            = "GLOBAL"
}

resource "google_compute_firewall" "allow-9000" {
  name    = "${var.company}-fw-allow-9000"
  network = "${google_compute_network.vpc.name}"
  allow {
    protocol = "tcp"
    ports    = ["9000"]
  }
  description = "hmy node"
}
resource "google_compute_firewall" "allow-9100" {
  name    = "${var.company}-fw-allow-9100"
  network = "${google_compute_network.vpc.name}"
  allow {
    protocol = "tcp"
    ports    = ["9100"]
  }
  description = "hmy grafana"
}
resource "google_compute_firewall" "allow-6000" {
  name    = "${var.company}-fw-allow-6000"
  network = "${google_compute_network.vpc.name}"
  allow {
    protocol = "tcp"
    ports    = ["6000"]
  }
  description = "hmy state syncing"
}
resource "google_compute_firewall" "allow-9500" {
  name    = "${var.company}-fw-allow-9500"
  network = "${google_compute_network.vpc.name}"
  allow {
    protocol = "tcp"
    ports    = ["9500"]
  }
  description = "hmy rpc"
}
resource "google_compute_firewall" "allow-bastion" {
  name          = "${var.company}-fw-allow-bastion"
  network       = "${google_compute_network.vpc.name}"
  source_ranges = ["35.160.64.190/32", "24.6.223.127/32", "52.37.248.195/32", "13.52.173.26/32", "73.170.34.104/32"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  description = "hmy bastion"
}

#module "init-us-east-1" {
#  source = "./setup"
#  region = "ue1"
#}

#module "init-us-east-2" {
#  source = "./setup"
#  region = "ue2"
#}
