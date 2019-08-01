# keypair for harmony nodes

resource "aws_key_pair" "auth" {
  key_name   = "harmony-node"
  public_key = "${file(var.public_key_path)}"
}
