terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
  }
}

# Default provider: the org's management account. Used to create the 3 demo
# member accounts (account.tf) and doubles as the OAM monitoring account —
# account_a's region (var.demo_accounts.account_a) is expected to match the
# region this provider block targets, since account_a and account_b are
# deliberately placed in the same region to demonstrate real cross-account
# OAM linking.
provider "aws" {
  region = var.demo_accounts["account_a"]
}

# One aliased provider per demo account (not per region) — each assumes into
# that specific account's own auto-created OrganizationAccountAccessRole and
# operates in that account's designated region. This is what lets a single
# `apply` manage resources inside 3 separate AWS accounts.
#
# assume_role is a no-op when create_account = false — the alias then just
# behaves like a plain regional provider against whatever account your
# default credentials belong to (useful for `terraform validate`/`plan`
# against an existing single account while iterating).
provider "aws" {
  alias  = "account_a"
  region = var.demo_accounts["account_a"]

  dynamic "assume_role" {
    for_each = var.create_account ? [1] : []
    content {
      role_arn = "arn:aws:iam::${aws_organizations_account.demo["account_a"].id}:role/OrganizationAccountAccessRole"
    }
  }
}

provider "aws" {
  alias  = "account_b"
  region = var.demo_accounts["account_b"]

  dynamic "assume_role" {
    for_each = var.create_account ? [1] : []
    content {
      role_arn = "arn:aws:iam::${aws_organizations_account.demo["account_b"].id}:role/OrganizationAccountAccessRole"
    }
  }
}

provider "aws" {
  alias  = "account_c"
  region = var.demo_accounts["account_c"]

  dynamic "assume_role" {
    for_each = var.create_account ? [1] : []
    content {
      role_arn = "arn:aws:iam::${aws_organizations_account.demo["account_c"].id}:role/OrganizationAccountAccessRole"
    }
  }
}

# Grafana Cloud provider, authenticated via a Cloud Access Policy token.
# Set via TF_VAR_grafana_cloud_access_policy_token from a gitignored .env, never in this file.
provider "grafana" {
  cloud_access_policy_token = var.grafana_cloud_access_policy_token
}
