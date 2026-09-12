output "id" {
  description = "Transit gateway VPC attachment ID."
  value       = aws_ec2_transit_gateway_vpc_attachment.tgw-attach.id
}
