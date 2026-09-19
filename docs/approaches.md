# Three ways to combine CloudWatch across accounts and regions

Most organizations end up with AWS resources spread across several accounts — for
billing isolation, security boundaries, or blast-radius control — and several regions
for latency or resilience. CloudWatch, by default, is siloed along both of those axes:
metrics, logs, and alarms live in the account and region where they were emitted. Getting
a single view across all of it means picking one (or more) of three approaches.

## Two boundaries, first

**An AWS account** is a billing, security, and blast-radius boundary. Resources in one
account are isolated from another by default — separate IAM, separate service limits,
separate invoices.

**An AWS Region** is a physical isolation boundary — a cluster of data centers in one
geography. Most AWS services, CloudWatch included, are regional: a metric published in
`us-east-1` doesn't exist in `eu-central-1` unless something explicitly moves it there.

Combining visibility across N accounts and M regions means solving both dimensions.

## Approach 1: Observability Access Manager (OAM)

AWS's current recommended default. You designate one account as the **monitoring
account** and others as **source accounts**, then link them:

- A **sink** is created in the monitoring account — one per Region — as the attachment
  point source accounts connect to.
- A **sink policy** authorizes which source accounts (or, more practically, which AWS
  Organization) may attach.
- A **link** is created in each source account, pointing at the monitoring account's
  sink, specifying which telemetry to share: metrics, logs, traces, or X-Ray.

Once linked, the monitoring account's CloudWatch console and APIs see source-account
telemetry natively — cross-account dashboards, alarms against remote metrics, and Logs
Insights queries all work as if the data were local.

**The catch: sinks and links cannot cross regions.** A monitoring account visible into 3
regions needs 3 sinks, and each source account needs a link per region into the matching
regional sink. There's no single global aggregation point inside OAM — you view region A
from the monitoring account's region A console, region B from its region B console.

This repo's demo makes that catch concrete with 3 real AWS accounts (see
[`terraform/account.tf`](../terraform/account.tf)): `account_a` is the OAM monitoring
account; `account_b` is deliberately placed in the *same* region as `account_a`, so it can
create a real cross-account link into `account_a`'s sink; `account_c` sits in a *different*
region on purpose and has no link at all — proving live that region, not just account
membership, gates whether OAM can connect two accounts.

**Cost**: source accounts pay normal CloudWatch/X-Ray rates; the monitoring account pays
for cross-account Logs Insights queries and API calls against shared data.

## Approach 2: Cross-account, cross-Region CloudWatch console

An older, IAM-role-based mechanism that predates OAM. A **sharing account** creates a
role (`CloudWatch-CrossAccountSharingRole`) trusting a monitoring account (or, scoped via
`aws:PrincipalOrgID`, an entire Organization). The monitoring account has a matching
service role (`ServiceRoleForCloudWatchCrossAccountV2`) that assumes it.

The interesting trade-off is the opposite of OAM's:

- **Cross-region is automatic and free** — metrics from any region show on the same
  graph or dashboard in the monitoring account, no per-region linking required.
- **Logs are not supported** across account/region boundaries at all.
- **Alarms are view-only** — you cannot create an alarm in the monitoring account that
  watches a metric living in a different account or region.

If what you want is genuinely just "one dashboard, many accounts, many regions, metrics
only," this older mechanism gets there with less setup than OAM. If you need logs,
traces, or cross-account alarms, it can't do it.

## Approach 3: Export/stream out of CloudWatch

Both approaches above are *viewing* mechanisms — the data still lives where it was
emitted; a monitoring account is granted read access to look at it in place. Sometimes
that's not enough:

- You want a single, queryable store spanning every account and region — not "log in
  and switch context," but one dataset.
- You want retention longer than CloudWatch's own limits.
- You want to feed a non-CloudWatch destination — Grafana, Datadog, a data warehouse.

The mechanism here is **CloudWatch Metric Streams** → **Kinesis Data Firehose** → a
destination. Firehose supports delivering straight to a supported third-party
integration — this repo's demo sends directly to **Grafana Cloud's CloudWatch Metric
Streams HTTP endpoint**, using the required OTLP 1.0 output format (Grafana's ingest
service does not accept the JSON output format for this integration). S3 is only
configured as a `FailedDataOnly` backup destination, not the primary data path — the
metrics land in Grafana directly, without a separate query layer (Athena, etc.) in
between.

Metric Streams must be declared in the account and region that actually emit the
metrics — a stream in one account only sees that account's own CloudWatch data. This
repo's demo therefore declares one Metric Stream + Firehose delivery stream per demo
account (see [`terraform/modules/metric-stream/`](../terraform/modules/metric-stream/)),
each streaming independently into the same Grafana Cloud stack — which is itself an
example of consolidation across accounts and regions into a single destination.

Cross-account log aggregation follows a parallel pattern using **CloudWatch Logs
subscription filters** shipping to a central destination.

## Comparison

| | OAM | Cross-account cross-Region console | Export/stream |
|---|---|---|---|
| Metrics | ✅ | ✅ | ✅ |
| Logs | ✅ | ❌ | via subscription filters |
| Traces / X-Ray | ✅ | view-only trace map | ❌ |
| Cross-region | per-region link required | automatic, free | per-region stream, shared destination |
| Cross-account alarms | ✅ | ❌ (view-only) | N/A — alarming happens on the exported copy |
| True data consolidation | ❌ (view, not copy) | ❌ (view, not copy) | ✅ |
| AWS's current recommendation | ✅ primary | legacy, still supported | for consolidation/3rd-party use cases |

## Sending it to Grafana Cloud

Grafana Cloud's CloudWatch data source authenticates via the **Grafana Assume Role**
method: you create an IAM role in your AWS account trusting Grafana Cloud's AWS account,
scoped with an `externalId` unique to your Grafana Cloud stack. Grafana's backend uses
STS to assume that role and pull CloudWatch data — no long-lived AWS access keys are
ever generated or stored.

- One CloudWatch data source **per region** is recommended for query performance.
- If you've already set up an OAM monitoring account that aggregates several source
  accounts, you can point Grafana's data source(s) at that single monitoring account
  instead of each source account individually — fewer IAM roles to manage, and it
  reuses the aggregation you already built.
- See [`terraform/grafana.tf`](../terraform/grafana.tf) for the illustrative Terraform.

## Which one, in practice

- Want the richest picture (metrics + logs + traces) and can tolerate per-region setup:
  **OAM**.
- Want just a metrics dashboard spanning accounts and regions with the least setup, and
  don't need cross-account alarms or logs: **the older console mechanism**.
- Want to consolidate into a real store you control, feed a 3rd-party tool like Grafana,
  or need retention beyond CloudWatch's limits: **Metric Streams / export**.

These aren't mutually exclusive — a common combination is OAM within each region for full
telemetry, plus the older console feature layered on top purely for one multi-region
metrics view, or OAM for internal AWS-console use plus Metric Streams feeding an external
Grafana Cloud stack for the "single pane of glass" that spans everything.
