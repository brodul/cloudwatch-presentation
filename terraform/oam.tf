# Approach 1: CloudWatch Observability Access Manager (OAM)
#
# account_a is the OAM monitoring account — the sink below is explicitly
# created there via the aws.account_a provider alias, not the org's
# management account (an earlier version of this conflated the two, which
# broke dashboard 2: Grafana's CloudWatch data source authenticates via a
# role in account_a, so a sink living anywhere else is invisible to it).
# account_b shares account_a's region on purpose, so it can create a real
# cross-account OAM link into account_a's sink. account_c sits in a
# different region — deliberately left without a link, to demonstrate that
# OAM sinks/links cannot cross regions: a monitoring account visible into
# account_c's region would need its own sink there too, plus a link created
# from account_c targeting it.

resource "aws_oam_sink" "monitoring" {
  provider = aws.account_a
  name     = "meetup-demo-monitoring-sink"
}

# Sink policy scoped to the whole AWS Organization, so any current or future
# member account in the same region as this sink can link to it.
resource "aws_oam_sink_policy" "monitoring" {
  provider        = aws.account_a
  sink_identifier = aws_oam_sink.monitoring.id

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

# Real cross-account link: created from account_b (same region as the sink),
# pointing at account_a's sink.
resource "aws_oam_link" "account_b" {
  provider        = aws.account_b
  sink_identifier = aws_oam_sink.monitoring.arn
  label_template  = "$AccountName"

  resource_types = [
    "AWS::CloudWatch::Metric",
    "AWS::Logs::LogGroup",
    "AWS::XRay::Trace",
  ]

  depends_on = [aws_oam_sink_policy.monitoring]
}

# No aws_oam_link is declared for account_c: it lives in a different region
# than the sink above, and OAM links must be created in the same region as
# the sink they target. Demonstrating this gap live is the point of including
# account_c at all — see docs/approaches.md.
