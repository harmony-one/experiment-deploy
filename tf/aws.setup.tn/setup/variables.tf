variable "region" {}

variable "public_key_path" {
  description = "The path to the SSH Public Key to add to AWS."
  default     = "~/.ssh/harmony-tn-node.pub"
}

variable "private_key_path" {
  description = "The path to the SSH Private Key to access ec2 instance."
  default     = "~/.ssh/harmony-tn-node.pem"
}

variable "node_owner" {
  description = "The user starts the node instance"
  default     = "LeoChen"
}
