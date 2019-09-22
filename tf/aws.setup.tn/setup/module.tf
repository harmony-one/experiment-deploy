terraform {
  required_version = ">= 0.12.6"
}

provider "aws" {
  region = "${var.region}"
}
