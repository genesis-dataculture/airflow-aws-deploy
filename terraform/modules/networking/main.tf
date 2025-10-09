# resource "aws_vpc" "airflow_vpc" {
#   cidr_block           = "10.0.0.0/16"
#   enable_dns_support   = true
#   enable_dns_hostnames = true

#   tags = {
#     Name = "airflow-vpc"
#   }
# }

# data "aws_availability_zones" "available" {}

# resource "aws_subnet" "public" {
#   count             = 2
#   vpc_id            = aws_vpc.airflow_vpc.id
#   cidr_block        = cidrsubnet(aws_vpc.airflow_vpc.cidr_block, 8, count.index)
#   availability_zone = data.aws_availability_zones.available.names[count.index]
#   map_public_ip_on_launch = true

#   tags = {
#     Name = "airflow-public-subnet-${count.index}"
#   }
# }

# resource "aws_subnet" "private" {
#   count             = 2
#   vpc_id            = aws_vpc.airflow_vpc.id
#   cidr_block        = cidrsubnet(aws_vpc.airflow_vpc.cidr_block, 8, count.index + 2)
#   availability_zone = data.aws_availability_zones.available.names[count.index]

#   tags = {
#     Name = "airflow-private-subnet-${count.index}"
#   }
# }

# resource "aws_internet_gateway" "gw" {
#   vpc_id = aws_vpc.airflow_vpc.id

#   tags = {
#     Name = "airflow-igw"
#   }
# }

# resource "aws_route_table" "public" {
#   vpc_id = aws_vpc.airflow_vpc.id

#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_internet_gateway.gw.id
#   }

#   tags = {
#     Name = "airflow-public-rt"
#   }
# }

# resource "aws_route_table_association" "public" {
#   count          = 2
#   subnet_id      = aws_subnet.public[count.index].id
#   route_table_id = aws_route_table.public.id
# }

# resource "aws_eip" "nat" {
#   domain = "vpc"

#   tags = {
#     Name = "airflow-nat-eip"
#   }
# }

# resource "aws_nat_gateway" "nat" {
#   allocation_id = aws_eip.nat.id
#   subnet_id     = aws_subnet.public[0].id

#   tags = {
#     Name = "airflow-nat"
#   }
# }

# resource "aws_route_table" "private" {
#   vpc_id = aws_vpc.airflow_vpc.id

#   route {
#     cidr_block     = "0.0.0.0/0"
#     nat_gateway_id = aws_nat_gateway.nat.id
#   }

#   tags = {
#     Name = "airflow-private-rt"
#   }
# }

# resource "aws_route_table_association" "private" {
#   count          = 2
#   subnet_id      = aws_subnet.private[count.index].id
#   route_table_id = aws_route_table.private.id
# }