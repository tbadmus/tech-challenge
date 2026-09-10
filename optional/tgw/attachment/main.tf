resource "aws_ec2_transit_gateway_vpc_attachment" "tgw-attach" {
  subnet_ids         = var.subnet_ids
  transit_gateway_id = var.tgw_id
  vpc_id             = var.vpc_id
}
