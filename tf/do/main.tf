provider "digitalocean" {
    token = var.do_token
}

resource "random_id" "droplet_id" {
    byte_length = 8
}

resource "digitalocean_droplet" "harmony_node" {
    name        = "node-s${var.shard}-${var.blskey_index}-${random_id.droplet_id.hex}"
    image       = var.droplet_system_image
    region      = var.droplet_region
    size        = var.droplet_size
    tags        = ["harmony"]
    # ssh_keys    = [digitalocean_ssh_key.harmony_ssh_key.fingerprint]
    ssh_keys = [25624276]
    volume_ids  = [digitalocean_volume.harmony_data_volume.id]
    resize_disk = "false"
    depends_on = [digitalocean_volume.harmony_data_volume]
}

resource "digitalocean_volume" "harmony_data_volume" {
    region                  = var.droplet_region
    name                    = "volume-s${var.shard}-${var.blskey_index}-${random_id.droplet_id.hex}"
    size                    = var.addition_volume_size
    initial_filesystem_type = "ext4"
    description             = "the data volume of harmony foundational node"
}

resource "digitalocean_firewall" "harmony_fw" {
    name = "harmony-fw"

    droplet_ids = [digitalocean_droplet.harmony_node.id]

    inbound_rule {
        protocol         = "tcp"
        port_range       = "22"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }

    inbound_rule {
        protocol         = "tcp"
        port_range       = "9000"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }

    inbound_rule {
        protocol         = "tcp"
        port_range       = "9800"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }

    inbound_rule {
        protocol         = "tcp"
        port_range       = "6000"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }

    inbound_rule {
        protocol         = "tcp"
        port_range       = "9500"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }
}

# test on Andy's local env
# resource "digitalocean_ssh_key" "harmony_ssh_key" {
#   name       = "Harmony Pub Key"
#   public_key = file("/Users/bwu2/.ssh/id_rsa.pub")
# }