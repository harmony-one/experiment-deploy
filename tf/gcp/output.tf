// A variable for extracting the external ip of the instance
output "ip" {
  value = "${google_compute_instance.fn.network_interface.0.access_config.0.nat_ip}"
}

output "name" {
  value = "${google_compute_instance.fn.name}"
}
