# CloudWatch Cross-Account / Cross-Region Reference

Reference material — and a real, working demo — for combining Amazon CloudWatch metrics
across multiple AWS accounts and multiple regions, shipped into Grafana Cloud three
different ways. Built for a 15-minute AWS meetup talk and a companion blog post.

## What this repo can do

**By default it's inert.** Account IDs, org IDs, and Grafana stack IDs are all Terraform
variables with fake placeholder defaults, and everything that creates real infrastructure
(new AWS accounts, EC2 instances) is gated behind `create_account` / `create_ec2_instances`
variables that default to `false` — cloning and running `terraform plan` with no overrides
provisions nothing.

**It can also be run for real.** Copy `terraform/terraform.tfvars.example` to a gitignored
`terraform/terraform.tfvars`, fill in real values, flip the two switches above to `true`,
and apply — this actually stands up 3 separate AWS accounts and wires all three
cross-account/cross-region approaches end to end into a real Grafana Cloud stack. That's
what's currently deployed; see "Current live demo state" below.

## The three approaches

1. **OAM (Observability Access Manager)** — AWS's current recommended default. Per-region
   sink/link resources unify metrics, logs, and traces into one monitoring account.
2. **Cross-account cross-Region console** — older IAM-role mechanism
   (`CloudWatch-CrossAccountSharingRole`). Metrics/dashboards/alarms view only, but gives
   free automatic cross-region graphing with no per-region setup.
3. **Export/stream out of CloudWatch** — Metric Streams → Kinesis Firehose → a destination.
   This demo streams directly into Grafana Cloud's CloudWatch Metric Streams HTTP endpoint
   (OTLP 1.0 format), not through S3/Athena — S3 is only a `FailedDataOnly` backup.

See [`docs/approaches.md`](docs/approaches.md) for the full comparison, trade-offs, and
when to pick which.

## Real infrastructure design

Three separate AWS member accounts, deliberately arranged to make the approaches'
differences concrete rather than just described:

- **`account_a`** (`us-east-1`) — the OAM monitoring account.
- **`account_b`** (`us-east-1`, same region as `account_a`) — creates a real cross-account
  OAM link into `account_a`'s sink. Proves OAM actually works cross-account.
- **`account_c`** (`us-west-2`, a different region) — deliberately has **no** OAM link.
  Demonstrates live that OAM sinks/links cannot cross regions — not just documentation,
  an observable gap in the monitoring account's view.

Each account gets one small EC2 instance (`t3.micro`) purely to emit real CloudWatch
metrics (`modules/demo-ec2/`). Each account also runs its own CloudWatch Metric Stream +
Firehose delivery stream (`modules/metric-stream/`), since Metric Streams only capture
metrics local to the account/region they're declared in — there is no single
account-spanning stream.

Because `aws_organizations_account` can only be created from the org's management account,
and Terraform provider blocks can't reference a resource created in the same apply, this
is a **two-phase apply**:

1. **Phase 1** — create the 3 accounts only: `terraform apply -target=aws_organizations_account.demo`
2. Copy the resulting real account IDs into `terraform.tfvars`' `demo_account_ids` map.
3. **Phase 2** — plain `terraform apply` — this is what actually assumes into each new
   account (via its auto-created `OrganizationAccountAccessRole`) and creates the EC2
   instances, OAM sink/link, Metric Streams, and Grafana resources inside them.

## Grafana Cloud integration

- **CloudWatch data sources** (`grafana_data_source.cloudwatch`, one per region) — the
  Grafana Assume Role method: an IAM role in `account_a` trusts Grafana Labs' AWS account
  via an external ID, no long-lived AWS keys involved. The role also carries
  `oam:ListSinks` / `oam:ListAttachedLinks`, which Grafana's CloudWatch data source
  specifically needs to discover and traverse OAM-shared cross-account metrics —
  `CloudWatchReadOnlyAccess` alone is not sufficient for that. Backs dashboards 1 and 2.
- **Prometheus data source** (`grafana_data_source.prometheus_otlp`) — points at the
  stack's own hosted Prometheus, where Approach 3's OTLP metrics land. Backs dashboard 3.
- Three separate, narrowly-scoped Grafana Cloud access policy tokens, matching the
  principle of least privilege per integration: `stack-service-accounts:write` (managing
  Grafana resources via Terraform), `metrics:write` (Firehose → Grafana ingestion),
  `metrics:read` (the Prometheus data source's own queries).
- Three dashboards, all defined in Terraform (`grafana_dashboard` resources in
  `grafana.tf`), not clicked together by hand:
  - **`cw-cross-account-demo`** — deliberately *not* a cross-account demo: every
    `grafana_data_source.cloudwatch` entry assumes the same role in `account_a`, so all
    panels here query `account_a` only, regardless of which region's data source is used.
    Only the `us-east-1` panels show data (that's the only region `account_a` has an
    instance in) — the `us-west-2`/`eu-central-1` panels are empty for a mundane
    single-account reason, not a cross-region limitation. Exists to make that distinction
    concrete before dashboard 2 introduces real cross-account access.
  - **`oam-cross-account-view`** — the actual Approach 1 cross-account story:
    `account_a`'s data source (now OAM-aware, see above) surfacing `account_b`'s metrics
    through the real link created in `oam.tf`, with an annotation explaining why
    `account_c` is absent (different region, no link).
  - **`metric-streams-otlp`** — Approach 3: Prometheus-backed panels querying the metrics
    delivered via Metric Streams/Firehose, independent of the CloudWatch API entirely.

## Current live demo state

At last apply: 3 real AWS accounts exist and are billing (see `docs/approaches.md` for the
teardown/cost notes), 3 EC2 instances are running, and all three approaches are wired into
Grafana Cloud stack `boldiguana716`. Tear down with `terraform destroy` when done — note
`aws_organizations_account` has `prevent_destroy = true`, so closing the accounts needs
that lifecycle block removed first or handling manually via the Organizations console.

## Contents

- [`slides/cloudwatch-meetup.md`](slides/cloudwatch-meetup.md) — 10-slide reveal.js deck.
- [`docs/approaches.md`](docs/approaches.md) — the three approaches compared in depth;
  source material for the blog post.
- [`terraform/`](terraform/):
  - `account.tf` — the 3 demo AWS accounts (phase 1)
  - `providers.tf` — per-account provider aliases (assume-role into each new account)
  - `ec2.tf` / `modules/demo-ec2/` — one EC2 instance per account
  - `oam.tf` — Approach 1: OAM sink + cross-account link
  - `cross-account-console.tf` — Approach 2: IAM roles for the older console mechanism
  - `metric-streams.tf` / `modules/metric-stream/` — Approach 3: per-account Metric
    Streams → Firehose → Grafana Cloud
  - `grafana.tf` — Grafana Cloud data sources, access policy tokens, and dashboards

## Running / viewing the slides

```
npx reveal-md slides/cloudwatch-meetup.md
```

## License

MIT — see [LICENSE](LICENSE).
