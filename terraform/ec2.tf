# Optional: launch one small EC2 instance per region to generate real
# CloudWatch metrics for the OAM/cross-account setup to aggregate. Gated
# behind var.create_ec2_instances (default false) — off by default so cloning
# and planning this repo stays inert.

module "demo_instance_us_east_1" {
  count  = var.create_ec2_instances ? 1 : 0
  source = "./modules/demo-ec2"

  providers = {
    aws = aws.us_east_1
  }

  name             = "cw-demo-us-east-1"
  allowed_ssh_cidr = var.allowed_ssh_cidr
}

module "demo_instance_us_west_2" {
  count  = var.create_ec2_instances ? 1 : 0
  source = "./modules/demo-ec2"

  providers = {
    aws = aws.us_west_2
  }

  name             = "cw-demo-us-west-2"
  allowed_ssh_cidr = var.allowed_ssh_cidr
}

module "demo_instance_eu_central_1" {
  count  = var.create_ec2_instances ? 1 : 0
  source = "./modules/demo-ec2"

  providers = {
    aws = aws.eu_central_1
  }

  name             = "cw-demo-eu-central-1"
  allowed_ssh_cidr = var.allowed_ssh_cidr
}
