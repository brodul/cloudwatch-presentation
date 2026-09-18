# Optional: create a new AWS member account for this demo, gated behind
# var.create_account (default false). Left off by default so cloning and
# planning this repo stays inert — set create_account = true in your own
# gitignored terraform.tfvars to actually provision one.

resource "aws_organizations_account" "demo" {
  count = var.create_account ? 1 : 0

  name      = var.demo_account_name
  email     = var.demo_account_email
  parent_id = var.demo_account_parent_ou_id

  # Avoid an accidental `terraform destroy` closing a real AWS account.
  lifecycle {
    prevent_destroy = true
  }
}
