# Minimal single EC2 instance in the default VPC, purely to have something
# emitting CloudWatch metrics (CPUUtilization etc.) for the demo. No EIP, no
# custom VPC — smallest footprint that still shows up in CloudWatch.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Not every AZ in a region supports every instance type (e.g. some
# us-east-1 AZs lack t3.micro) — filter subnets down to AZs that actually
# offer var.instance_type before picking one, rather than blindly using
# the first subnet returned.
data "aws_ec2_instance_type_offerings" "available" {
  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }

  location_type = "availability-zone"
}

data "aws_subnet" "candidates" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "demo" {
  name        = "${var.name}-sg"
  description = "Demo instance: SSH from a single trusted CIDR only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from trusted CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-sg"
  }
}

locals {
  # sort() makes this deterministic across plans — for_each/data source
  # ordering over a set is otherwise unspecified, which would make
  # supported_subnet_ids[0] flap between runs and force needless instance
  # replacement.
  supported_subnet_ids = sort([
    for id, subnet in data.aws_subnet.candidates :
    id if contains(data.aws_ec2_instance_type_offerings.available.locations, subnet.availability_zone)
  ])
}

resource "aws_instance" "demo" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = local.supported_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.demo.id]

  tags = {
    Name    = var.name
    Purpose = "cloudwatch-cross-account-demo"
  }
}

output "instance_id" {
  value = aws_instance.demo.id
}
