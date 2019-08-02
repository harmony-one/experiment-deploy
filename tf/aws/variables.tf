# variables for ec2 instances

variable "public_key_path" {
  description = "The path to the SSH Public Key to add to AWS."
  default = "keys/harmony-node.pub"
}

variable "private_key_path" {
  description = "The path to the SSH Private Key to access ec2 instance."
  default = "~/.ssh/harmony-node.pem"
}

variable "node_volume_size" {
  description = "Root Volume size of the ec2 node instance"
  default     = 50
}

variable "node_instance_type" {
  description = "Instance type of the ec2 node instance"
  default     = "t3.small"
}

variable "aws_region" {
  description = "Region user wants to run node instance in"
  default = "us-east-1"
}

variable "node_owner" {
  description = "The user starts the node instance"
  default = "LeoChen"
}

variable "spot_instance_price" {
  description = "The spot instance price"
  default = "0.0418"
}
