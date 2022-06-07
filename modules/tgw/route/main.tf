resource "aws_route" "tgwroute" {
  route_table_id         = var.route_table_id
  destination_cidr_block = var.destination_cidr_block
  transit_gateway_id     = var.tgw_id
}
