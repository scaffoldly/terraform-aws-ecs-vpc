# Reasonable design as per https://medium.com/aws-activate-startup-blog/practical-vpc-design-8412e1a18dcc
# CIDRs ranges adjusted to /20 to account for 6+ AZs in US-East-1
# 10.0.0.0/16:
#     10.0.0.0/20 — AZ A
#         10.0.0.0/21 — Private - cidrsubnet("10.0.0.0/16",5,0)  {0+2*count.index=0}
#         10.0.8.0/21
#                10.0.8.0/22 — Public - cidrsubnet("10.0.0.0/16",6,2)  {2+4*count.index=2}
#                10.0.12.0/22
#                    10.0.12.0/23 — Protected (No Internet Access) - cidrsubnet("10.0.0.0/16",7,6)  {6+8*count.index=?}
#                    10.0.14.0/23 — Build - cidrsubnet("10.0.0.0/16",7,7)
#     10.0.16.0/20 — AZ B
#         10.0.16.0/21 — Private - cidrsubnet("10.0.0.0/16",5,2)  {0+2*count.index=2}
#         10.0.24.0/21
#                 10.0.24.0/22 — Public - cidrsubnet("10.0.0.0/16",6,6)  {2+4*count.index=6}
#                 10.0.28.0/22
#                     10.0.28.0/23 — Protected - cidrsubnet("10.0.0.0/16",7,14)  {6+8*count.index=14}
#                     10.0.30.0/23 — Build - cidrsubnet("10.0.0.0/16",7,15)
#     10.0.32.0/20 — AZ C
#         10.0.32.0/21 — Private - cidrsubnet("10.0.0.0/16",5,4)  {0+2*count.index=4}
#         10.0.40.0/21
#                 10.0.40.0/22 — Public - cidrsubnet("10.0.0.0/16",6,10)  {2+4*count.index=10}
#                 10.0.44.0/22
#                     10.0.44.0/23 — Protected (No Internet Access) - cidrsubnet("10.0.0.0/16",7,22)  {6+8*count.index=22}
#                     10.0.46.0/23 — Build - cidrsubnet("10.0.0.0/16",7,23)
# ... and so on ...

//
// Base Resources
//
resource "aws_vpc" "vpc" {
  cidr_block           = "${var.cidr_block}"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-${data.aws_region.current.name}-${terraform.workspace}"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = "${aws_vpc.vpc.id}"
}

resource "aws_eip" "nat_eip" {
  vpc = true
}

//
// Subnets
//
resource "aws_subnet" "private" {
  count = "${length(data.aws_availability_zones.available.zone_ids)}"

  vpc_id                  = "${aws_vpc.vpc.id}"
  availability_zone_id    = "${data.aws_availability_zones.available.zone_ids[count.index]}"
  cidr_block              = "${cidrsubnet(var.cidr_block, 5, 0 + 2 * count.index)}"
  map_public_ip_on_launch = false

  tags = {
    Name = "ecs-${terraform.workspace}-private-${data.aws_availability_zones.available.zone_ids[count.index]}"
    Tier = "private"
  }
}

resource "aws_subnet" "public" {
  count = "${length(data.aws_availability_zones.available.zone_ids)}"

  vpc_id                  = "${aws_vpc.vpc.id}"
  availability_zone_id    = "${data.aws_availability_zones.available.zone_ids[count.index]}"
  cidr_block              = "${cidrsubnet(var.cidr_block, 6, 2 + 4 * count.index)}"
  map_public_ip_on_launch = true

  tags = {
    Name = "ecs-${terraform.workspace}-public-${data.aws_availability_zones.available.zone_ids[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "protected" {
  count = "${length(data.aws_availability_zones.available.zone_ids)}"

  vpc_id                  = "${aws_vpc.vpc.id}"
  availability_zone_id    = "${data.aws_availability_zones.available.zone_ids[count.index]}"
  cidr_block              = "${cidrsubnet(var.cidr_block, 7, 6 + 8 * count.index)}"
  map_public_ip_on_launch = false

  tags = {
    Name = "ecs-${terraform.workspace}-protected-${data.aws_availability_zones.available.zone_ids[count.index]}"
    Tier = "protected"
  }
}

resource "aws_subnet" "build" {
  count = "${length(data.aws_availability_zones.available.zone_ids)}"

  vpc_id                  = "${aws_vpc.vpc.id}"
  availability_zone_id    = "${data.aws_availability_zones.available.zone_ids[count.index]}"
  cidr_block              = "${cidrsubnet(var.cidr_block, 7, 7 + 8 * count.index)}"
  map_public_ip_on_launch = false

  tags = {
    Name = "ecs-${terraform.workspace}-build-${data.aws_availability_zones.available.zone_ids[count.index]}"
    Tier = "build"
  }
}

//
// Route Tables
//
resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = {
    Name = "ecs-${data.aws_region.current.name}-${terraform.workspace}-public"
    Tier = "public"
  }
}

resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = {
    Name = "ecs-${data.aws_region.current.name}-${terraform.workspace}-private"
    Tier = "private"
  }
}

resource "aws_route_table" "protected" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = {
    Name = "ecs-${data.aws_region.current.name}-${terraform.workspace}-protected"
    Tier = "protected"
  }
}

resource "aws_route_table" "build" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = {
    Name = "ecs-${data.aws_region.current.name}-${terraform.workspace}-build"
    Tier = "build"
  }
}

//
// Route Table Associations
//
resource "aws_route_table_association" "private" {
  count          = "${length(data.aws_availability_zones.available.zone_ids)}"
  subnet_id      = "${element(aws_subnet.private.*.id, count.index)}"
  route_table_id = "${aws_route_table.private.id}"
}

resource "aws_route_table_association" "public" {
  count          = "${length(data.aws_availability_zones.available.zone_ids)}"
  subnet_id      = "${element(aws_subnet.public.*.id, count.index)}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_route_table_association" "protected" {
  count          = "${length(data.aws_availability_zones.available.zone_ids)}"
  subnet_id      = "${element(aws_subnet.protected.*.id, count.index)}"
  route_table_id = "${aws_route_table.protected.id}"
}

resource "aws_route_table_association" "build" {
  count          = "${length(data.aws_availability_zones.available.zone_ids)}"
  subnet_id      = "${element(aws_subnet.build.*.id, count.index)}"
  route_table_id = "${aws_route_table.build.id}"
}

//
// NATs
//
resource "aws_nat_gateway" "aws_nat_gateway" {
  allocation_id = "${aws_eip.nat_eip.id}"
  subnet_id     = "${aws_subnet.public.0.id}"
  depends_on    = ["aws_internet_gateway.internet_gateway"]
}

//
// Routes to Gateways
//
resource "aws_route" "public_gateway" {
  route_table_id         = "${aws_route_table.public.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.internet_gateway.id}"
}

resource "aws_route" "private_gateway" {
  route_table_id         = "${aws_route_table.private.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${aws_nat_gateway.aws_nat_gateway.id}"
}

resource "aws_route" "build_gateway" {
  route_table_id         = "${aws_route_table.build.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${aws_nat_gateway.aws_nat_gateway.id}"
}

//
// Default to protected if anything new is created outside of Terraform
//
resource "aws_main_route_table_association" "main_route" {
  vpc_id         = "${aws_vpc.vpc.id}"
  route_table_id = "${aws_route_table.protected.id}"
}

resource "aws_cloudwatch_log_group" "vpc_logs" {
  name = "/aws/vpc/${aws_vpc.vpc.id}/flowlogs"
}

resource "aws_flow_log" "flow_log" {
  iam_role_arn    = "${data.aws_iam_role.vpc_logs.arn}"
  log_destination = "${aws_cloudwatch_log_group.vpc_logs.arn}"
  traffic_type    = "ALL"
  vpc_id          = "${aws_vpc.vpc.id}"
}
