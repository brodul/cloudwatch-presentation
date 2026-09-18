# Approach 2: Cross-account, cross-Region CloudWatch console
#
# Older IAM-role-based mechanism. Unlike OAM, cross-region graphing on a single
# dashboard is automatic here — no per-region link needed — but this approach
# only covers metrics/dashboards/alarms (view-only) and X-Ray trace map, not
# logs, and you cannot create an alarm in one account/region against a metric
# in another.

# Declared in each *sharing* (source) account. Trusts the monitoring account
# (or, as here, an entire AWS Organization) to assume this role read-only.
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

# Declared in the *monitoring* account. Lets CloudWatch assume the sharing
# role in any account belonging to the same organization.
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
