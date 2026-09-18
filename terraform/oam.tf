# Approach 1: CloudWatch Observability Access Manager (OAM)
#
# One sink per region in the monitoring account, one link per region per source
# account. Sinks and links cannot cross regions — a monitoring account that
# wants visibility into N regions needs a sink (and matching links) in each of
# those N regions.

resource "aws_oam_sink" "monitoring" {
  for_each = toset(var.regions)

  provider = aws # swap for the appropriate regional alias when adapting this
  name     = "meetup-demo-monitoring-sink-${each.key}"
}

# Sink policy scoped to the whole AWS Organization, matching this example's
# pattern of trusting by org membership rather than listing individual
# accounts one by one.
resource "aws_oam_sink_policy" "monitoring" {
  for_each = aws_oam_sink.monitoring

  sink_identifier = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OrganizationLinkPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "oam:CreateLink",
          "oam:UpdateLink",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = data.aws_organizations_organization.this.id
          },
          "ForAllValues:StringEquals" = {
            "oam:ResourceTypes" = [
              "AWS::CloudWatch::Metric",
              "AWS::Logs::LogGroup",
              "AWS::XRay::Trace",
            ]
          }
        }
      }
    ]
  })
}

# Example link from a source account into the monitoring account's sink for
# one region. In practice this resource is declared/applied from within each
# source account, once per region, against the matching regional sink ARN.
resource "aws_oam_link" "source_example" {
  for_each = toset(var.regions)

  provider        = aws
  sink_identifier = aws_oam_sink.monitoring[each.key].id
  label_template  = "$AccountName"

  resource_types = [
    "AWS::CloudWatch::Metric",
    "AWS::Logs::LogGroup",
    "AWS::XRay::Trace",
  ]
}
