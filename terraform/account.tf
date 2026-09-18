# Optional: create the 3 demo member accounts defined in var.demo_accounts,
# gated behind var.create_account (default false). Left off by default so
# cloning and planning this repo stays inert — set create_account = true in
# your own gitignored terraform.tfvars to actually provision these.
#
# aws_organizations_account can only be called from the org's management
# account (the default, unaliased "aws" provider here is expected to
# authenticate as that management account). Each new account gets AWS's
# auto-created "OrganizationAccountAccessRole", which the per-account
# provider blocks in providers.tf assume into — that's how a single `apply`
# can manage resources inside 3 separate, brand-new accounts.

resource "aws_organizations_account" "demo" {
  for_each = var.create_account ? var.demo_accounts : {}

  name      = "${var.demo_account_name}-${each.key}"
  email     = replace(var.demo_account_email, "@", "+${each.key}@")
  parent_id = var.demo_account_parent_ou_id

  # Avoid an accidental `terraform destroy` closing a real AWS account.
  lifecycle {
    prevent_destroy = true
  }
}
