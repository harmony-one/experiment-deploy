// output public ip
output "public_ip" {
  value = digitalocean_droplet.harmony_node.ipv4_address
}

