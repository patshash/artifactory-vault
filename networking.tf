resource "aws_vpc" "sandpit" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.sandpit.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = { for index, cidr in var.public_subnet_cidrs : index => cidr }

  vpc_id                  = aws_vpc.sandpit.id
  cidr_block              = each.value
  availability_zone       = local.availability_zones[tonumber(each.key)]
  map_public_ip_on_launch = false

  tags = {
    Name = format("%s-public-%02d", local.name_prefix, tonumber(each.key) + 1)
    Tier = "public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.sandpit.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
