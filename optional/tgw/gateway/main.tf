resource "aws_ec2_transit_gateway" "main" {
  description = var.tgw_name
  tags = {
    "Name" = var.tgw_name
  }
}
