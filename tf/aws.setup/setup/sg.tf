# Security Group with Harmoney Node ports enabled

resource "aws_security_group" "harmony-node-sg" {
  name        = "Harmony Node Security Group"
  description = "Security group for Harmony Nodes"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["24.6.223.94/32"]
    description = "Enable SSH from MTV office wifi"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["73.170.34.104/32"]
    description = "Enable SSH from Leo Home wifi"
  }

  ingress {
    from_port   = 6000
    to_port     = 6000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Harmony Node State Syncing Port"
  }

  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Harmony Basic Port"
  }

  ingress {
    from_port   = 14555
    to_port     = 14555
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Harmony RPC Port"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "Harmony Node Security Group"
    Project = "Harmony"
  }
}
