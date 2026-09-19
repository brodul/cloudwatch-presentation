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
# Deliberately driven by var.demo_account_ids (a plain variable), not
# aws_organizations_account.demo[...].id — provider blocks are configured
# before the resource graph resolves, so referencing a resource created in
# the same apply here would be a cycle. Phase 1: create the accounts with
# demo_account_ids left empty (assume_role becomes a no-op, so phase 1's
# resources land in your default/management-account credentials, which is
# fine since phase 1 only touches aws_organizations_account). Phase 2: paste
# the resulting real account IDs into demo_account_ids, then apply again —
# now these providers assume into the right accounts for everything else.
provider "aws" {
  alias  = "account_a"
  region = var.demo_accounts["account_a"]

  dynamic "assume_role" {
    for_each = var.demo_account_ids["account_a"] != "" ? [1] : []
    content {
      role_arn = "arn:aws:iam::${var.demo_account_ids["account_a"]}:role/OrganizationAccountAccessRole"
    }
  }
}

provider "aws" {
  alias  = "account_b"
  region = var.demo_accounts["account_b"]

  dynamic "assume_role" {
    for_each = var.demo_account_ids["account_b"] != "" ? [1] : []
    content {
      role_arn = "arn:aws:iam::${var.demo_account_ids["account_b"]}:role/OrganizationAccountAccessRole"
    }
  }
}

provider "aws" {
  alias  = "account_c"
  region = var.demo_accounts["account_c"]

  dynamic "assume_role" {
    for_each = var.demo_account_ids["account_c"] != "" ? [1] : []
    content {
      role_arn = "arn:aws:iam::${var.demo_account_ids["account_c"]}:role/OrganizationAccountAccessRole"
    }
  }
}

# Grafana Cloud Portal-level provider, authenticated via a Cloud Access
# Policy token. Only used for Cloud Portal API calls (looking up the stack,
# creating a stack-scoped service account/token below) — it cannot create
# resources like data sources *inside* a stack's own Grafana instance.
# Set via TF_VAR_grafana_cloud_access_policy_token from a gitignored .env, never in this file.
provider "grafana" {
  cloud_access_policy_token = var.grafana_cloud_access_policy_token
}

# Stack-scoped provider: authenticates directly against the target stack's
# own Grafana instance (not the Cloud Portal), using the service account
# token created in grafana.tf. This is what can create grafana_data_source
# and other in-stack resources.
provider "grafana" {
  alias = "stack"
  url   = data.grafana_cloud_stack.this.url
  auth  = grafana_cloud_stack_service_account_token.this.key
}
