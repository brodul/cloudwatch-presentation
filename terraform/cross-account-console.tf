# Approach 2: Cross-account, cross-Region CloudWatch console. Older IAM-role
# mechanism - unlike OAM, cross-region graphing is automatic, but it's
# metrics/dashboards/alarms (view-only) + X-Ray trace map only, no logs, and
# no cross-account/region alarms.

# Declared in each sharing (source) account — account_b and account_c, not
# account_a itself, since account_a is the monitoring account here and has
# nothing to share into itself. Trusts the monitoring account (here, the
# whole Organization) to assume this role read-only.
#
# Must be created via each source account's own provider alias — without an
# explicit `provider`, this would default to the un-aliased provider (the
# org's management account), which is not one of the 3 demo accounts at all.
resource "aws_iam_role" "cross_account_sharing_b" {
  provider = aws.account_b
  name     = "CloudWatch-CrossAccountSharingRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = data.aws_organizations_organization.this.id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cross_account_sharing_readonly_b" {
  provider   = aws.account_b
  role       = aws_iam_role.cross_account_sharing_b.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_iam_role" "cross_account_sharing_c" {
  provider = aws.account_c
  name     = "CloudWatch-CrossAccountSharingRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = data.aws_organizations_organization.this.id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cross_account_sharing_readonly_c" {
  provider   = aws.account_c
  role       = aws_iam_role.cross_account_sharing_c.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# NOTE: this resource has no `provider`, so it uses the default (un-aliased)
# provider — the org's management account, not account_a. That's a bug: the
# real monitoring account for this demo is account_a, and its own copy of
# this role was actually created by AWS itself when the cross-account
# console setup wizard was run there directly (with a SourceAccount/SourceArn
# condition Terraform doesn't generate) — this resource is stale/unused.
# Left in place, unfixed, as a second live example of the same "no explicit
# provider" mistake documented in docs/gotchas.md; not corrected to avoid
# fighting the wizard-created role already in account_a.
#
# Declared in the monitoring account; lets CloudWatch assume the sharing
# role in any account in the same organization.
resource "aws_iam_role" "monitoring_service_role" {
  name = "ServiceRoleForCloudWatchCrossAccountV2"
  path = "/service-role/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch-crossaccount.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  inline_policy {
    name = "CrossAccountAccess"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = "sts:AssumeRole"
          Resource = "arn:aws:iam::*:role/CloudWatch-CrossAccountSharingRole"
          Condition = {
            StringEquals = {
              "aws:ResourceOrgID" = data.aws_organizations_organization.this.id
            }
          }
        }
      ]
    })
  }
}

# NOT managed here on purpose. The "AWS Organization account selector"
# option (CloudWatch Settings → View cross-account cross-region) needs a
# separate org-account-list role in the org's *management* account — but per
# AWS's own docs, this is provisioned exclusively via a console-launched
# CloudFormation template (CloudWatch Settings, in the management account →
# "Grant permission to view the list of accounts in the organization" →
# Configure → Specific accounts → Launch CloudFormation template), not a
# documented/stable IAM shape meant to be hand-authored. The resulting role
# is named CloudWatch-CrossAccountListAccountsRole (or
# CloudWatch-CrossAccountSharing-ListAccountsRole per the doc's cleanup
# section — AWS's own docs aren't even consistent on the name), which is a
# signal it's implementation detail, not public API to pin in Terraform.
# See https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Cross-Account-Cross-Region.html#cross-account-and-AWS-organizations.
#
# If you don't need the org dropdown, use the "Account Id Input" or "Custom
# account selector" option instead when enabling the monitoring account —
# both work with only the roles Terraform already manages above.
