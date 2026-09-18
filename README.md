# CloudWatch Cross-Account / Cross-Region Reference

Illustrative reference material for combining Amazon CloudWatch metrics (and logs/traces)
across multiple AWS accounts and multiple regions, plus shipping the result into Grafana
Cloud. Built for a 15-minute AWS meetup talk and a companion blog post.

**This is reference code, not a deployable stack.** Nothing here defaults to creating
billable resources (no EC2 instances, no new AWS accounts). Account IDs, org IDs, and
Grafana stack IDs are all Terraform variables with clearly-fake placeholder defaults —
adapt them to your own environment before running `terraform apply` against anything.

## Contents

- [`slides/cloudwatch-meetup.md`](slides/cloudwatch-meetup.md) — 10-slide reveal.js deck.
- [`docs/approaches.md`](docs/approaches.md) — the three approaches compared in depth;
  source material for the blog post.
- [`terraform/`](terraform/) — illustrative Terraform for each approach:
  - `oam.tf` — Approach 1: CloudWatch Observability Access Manager (sinks/links)
  - `cross-account-console.tf` — Approach 2: cross-account cross-Region console (IAM roles)
  - `metric-streams.tf` — Approach 3: Metric Streams → Firehose → S3
  - `grafana.tf` — Grafana Cloud CloudWatch data source via the Grafana Assume Role method

## The three approaches, in one sentence each

1. **OAM (Observability Access Manager)** — AWS's current recommended default; per-region
   sink/link resources unify metrics, logs, and traces into one monitoring account.
2. **Cross-account cross-Region console** — older IAM-role mechanism
   (`CloudWatch-CrossAccountSharingRole`); metrics/dashboards/alarms view only, but gives
   free automatic cross-region graphing with no per-region setup.
3. **Export/stream out of CloudWatch** — Metric Streams → Kinesis Firehose → S3 or a
   third-party sink like Grafana Cloud; the only path to true consolidation, long
   retention, or a single store spanning regions.

See [`docs/approaches.md`](docs/approaches.md) for the full comparison, trade-offs, and
when to pick which.

## Running / viewing the slides

```
npx reveal-md slides/cloudwatch-meetup.md
```

## License

MIT — see [LICENSE](LICENSE).
