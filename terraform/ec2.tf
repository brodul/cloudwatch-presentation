# Optional: launch one small EC2 instance in each of the 3 demo accounts to
# generate real CloudWatch metrics for the OAM/cross-account setup to
# aggregate. Gated behind var.create_ec2_instances (default false) — off by
# default so cloning and planning this repo stays inert.

module "demo_instance_account_a" {
  count  = var.create_ec2_instances ? 1 : 0
  source = "./modules/demo-ec2"

  providers = {
    aws = aws.account_a
  }

  name             = "cw-demo-account-a"
  allowed_ssh_cidr = var.allowed_ssh_cidr
}

module "demo_instance_account_b" {
  count  = var.create_ec2_instances ? 1 : 0
  source = "./modules/demo-ec2"

  providers = {
    aws = aws.account_b
  }

  name             = "cw-demo-account-b"
  allowed_ssh_cidr = var.allowed_ssh_cidr
}

module "demo_instance_account_c" {
  count  = var.create_ec2_instances ? 1 : 0
  source = "./modules/demo-ec2"

  providers = {
    aws = aws.account_c
  }

  name             = "cw-demo-account-c"
  allowed_ssh_cidr = var.allowed_ssh_cidr
}
