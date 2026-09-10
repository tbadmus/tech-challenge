# Creating custom VPC for given CIDR
resource "aws_vpc" "main" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    "Name" = local.name
  }
}

# Creating public subnets distributed among all availability zones
resource "aws_subnet" "pub-subnets" {
  vpc_id                  = aws_vpc.main.id
  count                   = var.is_public_required ? local.count : 0
  cidr_block              = cidrsubnet(var.cidr, 5, count.index + 1)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    "Name"                                      = "${local.name}-pub-subnet-${substr(data.aws_availability_zones.available.names[count.index], -2, min(2, length(data.aws_availability_zones.available.names[count.index])))}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

# Creating private subnets distributed among all availability zones
resource "aws_subnet" "priv-subnets" {
  vpc_id                  = aws_vpc.main.id
  count                   = local.count
  cidr_block              = cidrsubnet(var.cidr, 5, count.index + 12)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags = {
    "Name"                                      = "${local.name}-priv-subnet-${substr(data.aws_availability_zones.available.names[count.index], -2, min(2, length(data.aws_availability_zones.available.names[count.index])))}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

resource "aws_internet_gateway" "main" {
  count  = var.is_public_required ? 1 : 0
  vpc_id = aws_vpc.main.id
  tags = {
    "Name" = "${local.name}-igw"
  }
}

# Security group to allow SSH traffic from given IP range
resource "aws_security_group" "default" {
  name   = "${local.name}-sg"
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip_range]
  }

  tags = {
    "Name" = "${local.name}-sg"
  }
}

resource "aws_route_table" "public-route" {
  count  = var.is_public_required ? 1 : 0
  vpc_id = aws_vpc.main.id

  lifecycle {
    ignore_changes = [propagating_vgws]
  }

  tags = {
    "Name" = "${local.name}-public-rt"
  }
}

resource "aws_route" "public_route" {
  count                  = var.is_public_required ? 1 : 0
  route_table_id         = element(aws_route_table.public-route.*.id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = element(aws_internet_gateway.main.*.id, count.index)
}

resource "aws_route_table" "private-route" {
  vpc_id = aws_vpc.main.id

  lifecycle {
    ignore_changes = [propagating_vgws]
  }

  tags = {
    "Name" = "${local.name}-private-rt"
  }
}

resource "aws_route_table_association" "pub-route-assoc" {
  count          = var.is_public_required ? local.count : 0
  subnet_id      = element(aws_subnet.pub-subnets.*.id, count.index)
  route_table_id = element(aws_route_table.public-route.*.id, count.index)
}

resource "aws_route_table_association" "priv-route-assoc" {
  count          = local.count
  subnet_id      = element(aws_subnet.priv-subnets.*.id, count.index)
  route_table_id = aws_route_table.private-route.id
}

# `vpc = true` was removed in AWS provider v6; `domain` replaces it.
resource "aws_eip" "main" {
  count  = var.nat_gateway ? 1 : 0
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  count         = var.nat_gateway ? 1 : 0
  allocation_id = aws_eip.main[0].id
  subnet_id     = element(aws_subnet.pub-subnets.*.id, 0)

  tags = {
    "Name" = "${local.name}-nat-gw"
  }

}

resource "aws_route" "nat_route" {
  count                  = var.nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.private-route.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[0].id
}

# Customizing default network ACL
resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.main.default_network_acl_id

  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = var.allowed_ip_range
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = var.allowed_ip_range
    from_port  = 0
    to_port    = 0
  }

  lifecycle {
    ignore_changes = [subnet_ids]
  }
}