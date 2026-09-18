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

resource "aws_instance" "demo" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.demo.id]

  tags = {
    Name    = var.name
    Purpose = "cloudwatch-cross-account-demo"
  }
}

output "instance_id" {
  value = aws_instance.demo.id
}
