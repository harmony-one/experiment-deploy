output "sg_id" {
  value = ["${aws_security_group.harmony-node-sg.*.id}"]
}
