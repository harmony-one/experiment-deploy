# variables for ec2 instances

variable "public_key_path" {
  description = "The path to the SSH Public Key to add to AWS."
  default     = "keys/harmony-node.pub"
}

variable "private_key_path" {
  description = "The path to the SSH Private Key to access ec2 instance."
  default     = "~/.ssh/harmony-node.pem"
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
  default     = "us-east-1"
}

variable "node_owner" {
  description = "The user starts the node instance"
  default     = "LeoChen"
}

variable "spot_instance_price" {
  description = "The spot instance price"
  default     = "0.0418"
}

variable "security_groups" {
  type        = map
  description = "Security Group Map"
  default = {
    "us-east-1"      = "sg-032b5818cc974d5fe"
    "us-west-1"      = "sg-0bf1cfd7d434d1529"
    "eu-west-1"      = "sg-098f4f6083087e7b7"
    "ap-south-1"     = "sg-0f442a8f98b51a0a7"
    "us-west-2"      = "sg-001ee45a9e0b323ed"
    "sa-east-1"      = "sg-086efb28104d3844f"
    "ap-northeast-1" = "sg-07e5a78703eed4056"
    "ca-central-1"   = "sg-0c8dfcaf14aa9c1af"
    "ap-southeast-2" = "sg-023ce4debb2214697"
    "ap-southeast-1" = "sg-0c06913573701aa3d"
    "eu-west-2"      = "sg-02140857925dca3e4"
    "us-east-2"      = "sg-01ab93d4f87f7d99b"
    "ap-northeast-2" = "sg-06495886b08accbb9"
    "eu-central-1"   = "sg-0f3d6b406e28de3c7"
  }
}

variable "user_data" {
  description = "User Data for EC2 Instance"
  default     = "files/userdata.sh"
}

variable "default_key" {
  default = ""
}
