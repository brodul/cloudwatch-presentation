# Grafana Cloud CloudWatch data source, via the Grafana Assume Role method:
# Grafana Cloud's own AWS account assumes an IAM role you create, using STS
# with an externalID unique to your Grafana Cloud account — no long-lived
# AWS keys ever leave your account.
#
# One data source per region is recommended for query performance. Pointing
# a single data source at the OAM monitoring account's aggregated view
# (Approach 1) instead needs only one such role rather than one per region.

data "grafana_cloud_stack" "this" {
  slug = var.grafana_cloud_stack_slug
}

resource "aws_iam_role" "grafana_cloudwatch_read" {
  name = "grafana-cloud-cloudwatch-read"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          # Replace with Grafana Labs' published AWS account ID for the
          # Assume Role integration; see Grafana's CloudWatch data source docs.
          AWS = "arn:aws:iam::${var.monitoring_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.grafana_aws_external_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_cloudwatch_read" {
  role       = aws_iam_role.grafana_cloudwatch_read.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# grafana_data_source is created against a specific stack's own Grafana
# instance, not the Cloud Portal API — configure a second, stack-scoped
# "grafana" provider (using a management-key token from that stack) and pass
# it in via `providers = { grafana = grafana.stack }` when adapting this.
resource "grafana_data_source" "cloudwatch" {
  for_each = toset(var.regions)

  type = "cloudwatch"
  name = "cloudwatch-${each.key}"

  json_data_encoded = jsonencode({
    authType      = "arn"
    assumeRoleArn = aws_iam_role.grafana_cloudwatch_read.arn
    externalId    = var.grafana_aws_external_id
    defaultRegion = each.key
  })
}
