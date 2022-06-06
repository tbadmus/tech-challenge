output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_cidr" {
  value = data.aws_vpc.main.cidr_block
}

output "public_route_table_id" {
  value = var.is_public_required ? aws_route_table.public-route[0].id : ""
}

output "private_route_table_id" {
  value = aws_route_table.private-route.id
}

output "public_subnets" {
  value = var.is_public_required ? aws_subnet.pub-subnets.*.id : []
}

output "private_subnets" {
  value = aws_subnet.priv-subnets.*.id
}

output "sg_id" {
  value = aws_security_group.default.id
}
