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

# A stack-scoped service account + token, created via the Cloud Portal API,
# used solely to authenticate the aliased "grafana.stack" provider (see
# providers.tf) so it can create resources inside the stack's own Grafana
# instance rather than at the Cloud Portal level.
resource "grafana_cloud_stack_service_account" "terraform" {
  stack_slug = data.grafana_cloud_stack.this.slug
  name       = "terraform"
  role       = "Admin"
}

resource "grafana_cloud_stack_service_account_token" "this" {
  stack_slug         = data.grafana_cloud_stack.this.slug
  service_account_id = grafana_cloud_stack_service_account.terraform.id
  name               = "terraform"
}

# Separate, narrowly-scoped access policy + token for Approach 3 (Metric
# Streams -> Firehose -> Grafana Cloud): metrics:write only, distinct from
# the Admin-scoped stack service account token above which is used for
# managing Grafana resources (data sources, etc.) via Terraform.
resource "grafana_cloud_access_policy" "metrics_write" {
  region       = data.grafana_cloud_stack.this.region_slug
  name         = "metric-streams-write"
  display_name = "Metric Streams write"

  # metrics:write alone gets "authentication error: no credentials provided"
  # from the aws-metrics ingest path specifically (confirmed: the same token
  # DOES authenticate fine against the standard Prometheus remote-write
  # endpoint) - Grafana's own Terraform Provider Authentication docs list
  # integration-management:read/write alongside stacks:read as required
  # scopes in this area, so trying that combination here.
  scopes = ["metrics:write", "integration-management:read", "integration-management:write", "stacks:read"]

  realm {
    type       = "stack"
    identifier = data.grafana_cloud_stack.this.id
  }
}

resource "grafana_cloud_access_policy_token" "metrics_write" {
  region           = data.grafana_cloud_stack.this.region_slug
  access_policy_id = grafana_cloud_access_policy.metrics_write.policy_id
  name             = "metric-streams-write"
}

# metrics:read-scoped policy + token, used only to authenticate the
# Prometheus data source (dashboard 3) that queries the OTLP metrics
# delivered by Approach 3 — separate from metrics:write above and from the
# Admin-scoped stack service account token, which does not carry
# metrics:read for direct Prometheus API access.
resource "grafana_cloud_access_policy" "metrics_read" {
  region       = data.grafana_cloud_stack.this.region_slug
  name         = "metric-streams-read"
  display_name = "Metric Streams read"

  scopes = ["metrics:read"]

  realm {
    type       = "stack"
    identifier = data.grafana_cloud_stack.this.id
  }
}

resource "grafana_cloud_access_policy_token" "metrics_read" {
  region           = data.grafana_cloud_stack.this.region_slug
  access_policy_id = grafana_cloud_access_policy.metrics_read.policy_id
  name             = "metric-streams-read"
}

# Grafana's CloudWatch Metric Streams ingest endpoint is NOT otlp_url (that
# host - otlp-gateway-<region>.grafana.net - rejects every credential with
# "invalid"/"no credentials provided" errors, confirmed via direct curl
# testing against both Basic Auth and the X-Amz-Firehose-Access-Key header).
# The real ingest host is a distinct "aws-metric-streams-<cell>.<domain>"
# origin, derived from the Prometheus remote-write host: take the numeric
# cell id (the "prod-<N>" segment right after "prometheus-") and the domain
# after the first dot. E.g. prometheus_url
# "https://prometheus-prod-65-prod-eu-west-2.grafana.net" -> ingest host
# "https://aws-metric-streams-prod-65.grafana.net". Confirmed working via
# curl with the X-Amz-Firehose-Access-Key header (200 OK) - Firehose's own
# http_endpoint_configuration.access_key is delivered via that header, not
# as an Authorization: Basic value, which is why Basic Auth against ANY
# candidate host (including this correct one) fails with "no credentials
# provided" even though the credentials themselves are valid.
locals {
  grafana_prometheus_host         = split("/", data.grafana_cloud_stack.this.prometheus_url)[2]
  grafana_prometheus_cell_id      = regex("^prometheus-(prod-[0-9]+)-", local.grafana_prometheus_host)[0]
  grafana_prometheus_domain       = join(".", slice(split(".", local.grafana_prometheus_host), 1, length(split(".", local.grafana_prometheus_host))))
  grafana_metric_streams_endpoint = "https://aws-metric-streams-${local.grafana_prometheus_cell_id}.${local.grafana_prometheus_domain}/aws-metrics/api/v1/push"
}

# Role lives in account_a, the OAM monitoring account — Grafana reads
# aggregated cross-account CloudWatch data through this one role rather than
# needing a separate role/trust relationship per source account.
resource "aws_iam_role" "grafana_cloudwatch_read" {
  provider = aws.account_a
  name     = "grafana-cloud-cloudwatch-read"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          # Grafana Labs' published AWS account ID for the Assume Role
          # integration (not your own account) — see
          # https://grafana.com/docs/grafana/latest/datasources/aws-cloudwatch/aws-authentication/
          AWS = "arn:aws:iam::${var.grafana_labs_aws_account_id}:root"
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
  provider   = aws.account_a
  role       = aws_iam_role.grafana_cloudwatch_read.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# CloudWatchReadOnlyAccess alone is not enough for Grafana's CloudWatch data
# source to surface metrics shared via OAM (dashboard 2) — it additionally
# needs oam:ListSinks / oam:ListAttachedLinks to discover and traverse the
# cross-account link created in oam.tf. Without this, the OAM link exists
# but Grafana has no way to know about it.
resource "aws_iam_role_policy" "grafana_cloudwatch_read_oam" {
  provider = aws.account_a
  name     = "oam-discovery"
  role     = aws_iam_role.grafana_cloudwatch_read.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "oam:ListSinks",
          "oam:ListAttachedLinks",
        ]
        Resource = "*"
      }
    ]
  })
}

# "Grafana Assume Role" (the method that needs only an externalId, no AWS
# keys) is its own distinct authType value - "grafana_assume_role" - not
# "default"+assumeRoleArn (that combination is plain AWS-SDK-Default-then-
# assume-role, a different method) and not "arn" (not a real value at all).
# Grafana Cloud stacks don't have the bare "default" AWS-SDK-default method
# in their allowed_auth_providers list, so both of the earlier, wrong values
# failed identically with "trying to use non-allowed auth method default" -
# confirmed by reading the @grafana/aws-sdk package's actual auth type
# enum, which lists exactly: keys, credentials, default, ec2_iam_role, arn,
# grafana_assume_role. This was why every panel on dashboards 1 and 2 showed
# "No data" despite the IAM role, trust policy, and OAM link all being
# individually correct.
resource "grafana_data_source" "cloudwatch" {
  provider = grafana.stack
  for_each = toset(var.regions)

  type = "cloudwatch"
  name = "cloudwatch-${each.key}"

  json_data_encoded = jsonencode({
    authType      = "grafana_assume_role"
    assumeRoleArn = aws_iam_role.grafana_cloudwatch_read.arn
    externalId    = var.grafana_aws_external_id
    defaultRegion = each.key
  })
}

# Prometheus data source pointed at this stack's own hosted Prometheus,
# where CloudWatch's OTLP-format Metric Streams data (Approach 3) actually
# lands. Basic-auth'd with the metrics:read-scoped token above.
#
# prometheus_url alone (e.g. https://prometheus-prod-65-prod-eu-west-2.grafana.net)
# 404s on every Prometheus HTTP API path - Grafana Cloud's Mimir instance
# serves the Prometheus-compatible API under a required /api/prom prefix,
# confirmed by comparing against the stack's own default
# grafanacloud-<slug>-prom data source, whose url has that suffix.
resource "grafana_data_source" "prometheus_otlp" {
  provider = grafana.stack

  type = "prometheus"
  name = "cloudwatch-metric-streams-otlp"
  url  = "${data.grafana_cloud_stack.this.prometheus_url}/api/prom"

  basic_auth_enabled  = true
  basic_auth_username = tostring(data.grafana_cloud_stack.this.prometheus_user_id)

  json_data_encoded = jsonencode({
    httpMethod = "POST"
  })

  secure_json_data_encoded = jsonencode({
    basicAuthPassword = grafana_cloud_access_policy_token.metrics_read.token
  })
}

# Dashboard 1: a single account's (account_a's) own EC2 metrics, queried
# region by region through 3 separate CloudWatch data sources. This does
# NOT demonstrate cross-account access — every grafana_data_source.cloudwatch
# entry uses the same assumeRoleArn (aws_iam_role.grafana_cloudwatch_read,
# which lives in account_a only), so all 3 panels below are querying
# account_a regardless of which region's data source is used. Only the
# us-east-1 panel shows data, because that's the only region account_a has
# an EC2 instance in — the other two are empty for a mundane single-account
# reason, not because of any cross-region/cross-account limitation. See
# dashboard 2 (oam_cross_account_view) for the actual cross-account story.
locals {
  cloudwatch_panel_regions = {
    1 = "us-east-1"
    3 = "us-west-2"
    4 = "us-east-1"
    5 = "eu-central-1"
  }

  cloudwatch_panels = [
    {
      id      = 1
      title   = "account_a's EC2 CPUUtilization, queried in us-east-1 (where its instance actually is)"
      metric  = "CPUUtilization"
      stat    = "Average"
      gridPos = { h = 8, w = 12, x = 0, y = 0 }
    },
    {
      id      = 3
      title   = "Same account_a role, queried in us-west-2 - empty: account_a has no resources there"
      metric  = "CPUUtilization"
      stat    = "Average"
      gridPos = { h = 8, w = 12, x = 12, y = 0 }
    },
    {
      id      = 4
      title   = "account_a's EC2 NetworkIn (Sum), us-east-1"
      metric  = "NetworkIn"
      stat    = "Sum"
      gridPos = { h = 8, w = 12, x = 12, y = 8 }
    },
    {
      id      = 5
      title   = "Same account_a role, queried in eu-central-1 - empty for the same reason"
      metric  = "CPUUtilization"
      stat    = "Average"
      gridPos = { h = 8, w = 24, x = 0, y = 16 }
    },
  ]
}

# Dashboard 2: Approach 1 (OAM) cross-account view. account_b has no
# CloudWatch data source of its own in this repo — the point of OAM is that
# account_a's monitoring view sees account_b's metrics through the real
# cross-account link created in oam.tf, without account_b needing to be
# queried directly. This dashboard deliberately queries only the
# account_a-scoped ("us-east-1") data source, labelled to make clear that
# what's rendered may include account_b's shared telemetry via that link.
resource "grafana_dashboard" "oam_cross_account_view" {
  provider = grafana.stack

  config_json = jsonencode({
    title         = "1: OAM Cross-Account View"
    uid           = "oam-cross-account-view"
    timezone      = "browser"
    schemaVersion = 39
    refresh       = "30s"
    time          = { from = "now-1h", to = "now" }
    tags          = ["cloudwatch", "oam", "cross-account", "meetup-demo"]
    panels = [
      {
        id      = 1
        title   = "account_a's monitoring view (us-east-1) - EC2 CPUUtilization, all linked accounts"
        type    = "timeseries"
        gridPos = { h = 9, w = 24, x = 0, y = 0 }
        datasource = {
          type = "cloudwatch"
          uid  = grafana_data_source.cloudwatch["us-east-1"].uid
        }
        targets = [
          {
            namespace  = "AWS/EC2"
            metricName = "CPUUtilization"
            statistic  = "Average"
            # dimensions = {} triggers a wildcard SEARCH() and returns real
            # data via the backend API directly, but the frontend panel
            # renderer's own query editor/normalization logic requires at
            # least one dimension key with a wildcard value to treat this as
            # a valid multi-dimension search. InstanceId = "*" matches
            # Grafana's own documented CloudWatch query examples for this
            # pattern.
            dimensions = { InstanceId = "*" }
            matchExact = false
            region     = "us-east-1"
            refId      = "A"
            # metricEditorMode/metricQueryType/queryMode/accountId are all
            # required for the CloudWatch query *editor* to actually issue
            # the query in the browser - confirmed the hard way: queries
            # missing these fields returned real data via direct
            # /api/ds/query calls (backend plugin runs fine), but the
            # frontend never even fired a network request for the panel,
            # leaving it stuck on "No data" with no console error. Diffing
            # against Grafana's own re-save of this panel (after manually
            # re-picking the datasource in the UI) showed these 4 fields
            # were the only functional difference; accountId = "all" in
            # particular is what tells the editor to include OAM-shared
            # metrics from linked accounts, not just this account's own.
            accountId        = "all"
            metricEditorMode = 0
            metricQueryType  = 0
            queryMode        = "Metrics"
            datasource = {
              type = "cloudwatch"
              uid  = grafana_data_source.cloudwatch["us-east-1"].uid
            }
          }
        ]
      },
      {
        id      = 2
        title   = "Note: account_c (us-west-2) is deliberately NOT visible here - OAM links cannot cross regions"
        type    = "text"
        gridPos = { h = 3, w = 24, x = 0, y = 9 }
        options = {
          mode    = "markdown"
          content = "**account_c** lives in `us-west-2`, a different region than the OAM sink in `us-east-1`. Since OAM sinks/links cannot cross regions, account_c has no link into this monitoring view — its metrics are absent here on purpose. See `docs/approaches.md` for the full explanation."
        }
      }
    ]
  })
}

resource "grafana_dashboard" "cloudwatch_cross_account" {
  provider = grafana.stack

  config_json = jsonencode({
    title         = "CloudWatch Cross-Account/Region Basics (not one of the 3 approaches)"
    uid           = "cw-cross-account-demo"
    timezone      = "browser"
    schemaVersion = 39
    refresh       = "30s"
    time          = { from = "now-1h", to = "now" }
    tags          = ["cloudwatch", "meetup-demo"]
    panels = [
      for panel in local.cloudwatch_panels : {
        id      = panel.id
        title   = panel.title
        type    = "timeseries"
        gridPos = panel.gridPos
        datasource = {
          type = "cloudwatch"
          uid  = grafana_data_source.cloudwatch[local.cloudwatch_panel_regions[panel.id]].uid
        }
        targets = [
          {
            namespace  = "AWS/EC2"
            metricName = panel.metric
            statistic  = panel.stat
            # See the matching comment on dashboard 2's target: dimensions =
            # {} works via the raw backend API but the frontend panel
            # renderer needs a wildcarded dimension key to render, or it
            # shows "No data" despite the query succeeding server-side.
            dimensions = { InstanceId = "*" }
            matchExact = false
            region     = local.cloudwatch_panel_regions[panel.id]
            refId      = "A"
            # See the matching comment on dashboard 2's target - these 4
            # fields are required for the CloudWatch query editor to
            # actually fire the query in the browser.
            accountId        = "all"
            metricEditorMode = 0
            metricQueryType  = 0
            queryMode        = "Metrics"
            datasource = {
              type = "cloudwatch"
              uid  = grafana_data_source.cloudwatch[local.cloudwatch_panel_regions[panel.id]].uid
            }
          }
        ]
      }
    ]
  })
}

# Dashboard 3: Approach 3 (Metric Streams -> Firehose -> Grafana Cloud,
# OTLP). Queries Prometheus directly, entirely independent of the
# CloudWatch API/data sources used by dashboards 1 and 2 — this is what
# "true consolidation into one store" (docs/approaches.md) actually looks
# like end to end. Metric names follow CloudWatch's documented OTLP ->
# Prometheus convention: aws_<namespace>_<metricname>_<statistic>, e.g.
# aws_ec2_cpuutilization_average.
resource "grafana_dashboard" "metric_streams_otlp" {
  provider = grafana.stack

  config_json = jsonencode({
    title         = "3: Metric Streams (OTLP) via Grafana Prometheus"
    uid           = "metric-streams-otlp"
    timezone      = "browser"
    schemaVersion = 39
    refresh       = "30s"
    time          = { from = "now-1h", to = "now" }
    tags          = ["cloudwatch", "metric-streams", "otlp", "meetup-demo"]
    panels = [
      {
        id      = 1
        title   = "EC2 CPUUtilization (Average) by account/region - via OTLP, not the CloudWatch API"
        type    = "timeseries"
        gridPos = { h = 9, w = 24, x = 0, y = 0 }
        datasource = {
          type = "prometheus"
          uid  = grafana_data_source.prometheus_otlp.uid
        }
        targets = [
          {
            expr         = "aws_ec2_cpuutilization_average"
            legendFormat = "{{region}} - {{__name__}}"
            refId        = "A"
            datasource = {
              type = "prometheus"
              uid  = grafana_data_source.prometheus_otlp.uid
            }
          }
        ]
      },
      {
        id      = 2
        title   = "EC2 NetworkIn (Sum) by account/region - via OTLP"
        type    = "timeseries"
        gridPos = { h = 9, w = 24, x = 0, y = 9 }
        datasource = {
          type = "prometheus"
          uid  = grafana_data_source.prometheus_otlp.uid
        }
        targets = [
          {
            # Not aws_ec2_networkin_sum - CloudWatch's OTLP->Prometheus
            # naming inserts an underscore between "network" and the
            # direction word (confirmed via the actual __name__ label
            # values present in Mimir): aws_ec2_network_in_sum.
            expr         = "aws_ec2_network_in_sum"
            legendFormat = "{{region}} - {{__name__}}"
            refId        = "A"
            datasource = {
              type = "prometheus"
              uid  = grafana_data_source.prometheus_otlp.uid
            }
          }
        ]
      },
    ]
  })
}

# Dashboard 2: Approach 2 (cross-account, cross-Region CloudWatch console).
# Deliberately has NO live metrics panel - this is the one approach that
# cannot be represented in Grafana at all. Approach 2 works by configuring
# the *monitoring account's AWS Console* (CloudWatch -> Settings ->
# Monitoring account configuration) to assume the CloudWatch-
# CrossAccountSharingRole created per source account in
# cross-account-console.tf, and the merged cross-account/cross-region view
# only ever renders inside that AWS Console UI. Grafana's CloudWatch data
# source always authenticates with its own IAM role per data source (see
# grafana_data_source.cloudwatch above) and has no API equivalent of the
# console's "monitoring account configuration" feature - there is no
# metrics/log/API surface this dashboard could query that would actually
# demonstrate Approach 2 rather than just re-demonstrating Approach 1's
# plain per-account CloudWatch querying under a different label.
resource "grafana_dashboard" "cross_account_console" {
  provider = grafana.stack

  config_json = jsonencode({
    title         = "2: Cross-Account Console (not representable in Grafana)"
    uid           = "cross-account-console"
    timezone      = "browser"
    schemaVersion = 39
    refresh       = ""
    time          = { from = "now-1h", to = "now" }
    tags          = ["cloudwatch", "cross-account", "meetup-demo"]
    panels = [
      {
        id      = 1
        title   = "Why this dashboard has no metrics panel"
        type    = "text"
        gridPos = { h = 14, w = 24, x = 0, y = 0 }
        options = {
          mode = "markdown"
          content = join("\n", [
            "Approach 2 (the older IAM-role-based cross-account, cross-Region CloudWatch console mechanism) **cannot be shown in Grafana**.",
            "",
            "Unlike Approaches 1 (OAM) and 3 (Metric Streams), which expose data through APIs Grafana's CloudWatch/Prometheus data sources can call directly, Approach 2's cross-account view is rendered **only inside the AWS Console itself**:",
            "",
            "1. In the *monitoring account* (`account_a`), an admin visits **CloudWatch → Settings → Monitoring account configuration** and turns on cross-account observability, pointing it at the `ServiceRoleForCloudWatchCrossAccountV2` service role.",
            "2. That role assumes `CloudWatch-CrossAccountSharingRole` (created per *sharing* account - see [`terraform/cross-account-console.tf`](../terraform/cross-account-console.tf)) in any account belonging to the same AWS Organization.",
            "3. The merged view - metrics from every linked account and Region, on one graph, no per-region linking required - only appears in that AWS Console session. There is no separate API a third-party tool like Grafana can call to fetch \"the monitoring-account merged view\"; Grafana's CloudWatch data source always queries via its own assumed role, one region at a time, which is Approach 1's mechanism, not Approach 2's.",
            "",
            "**To see Approach 2 live:** sign in to the AWS Console as `account_a`, enable monitoring account configuration, and browse the CloudWatch metrics/dashboards/alarms console directly. See `docs/approaches.md` for the full comparison.",
          ])
        }
      }
    ]
  })
}
