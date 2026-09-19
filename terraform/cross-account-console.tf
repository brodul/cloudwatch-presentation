# Approach 2: Cross-account, cross-Region CloudWatch console. Older IAM-role
# mechanism - unlike OAM, cross-region graphing is automatic, but it's
# metrics/dashboards/alarms (view-only) + X-Ray trace map only, no logs, and
# no cross-account/region alarms.

# Declared in each sharing (source) account; trusts the monitoring account
# (here, the whole Organization) to assume this role read-only.
resource "aws_iam_role" "cross_account_sharing" {
  name = "CloudWatch-CrossAccountSharingRole"

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

resource "aws_iam_role_policy_attachment" "cross_account_sharing_readonly" {
  role       = aws_iam_role.cross_account_sharing.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

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
