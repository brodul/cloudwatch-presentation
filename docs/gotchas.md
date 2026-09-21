# Gotchas encountered building this demo

Things that broke in non-obvious ways while wiring up CloudWatch cross-account/
cross-region observability into Grafana Cloud, and how they were actually
diagnosed. Kept separate from `approaches.md` (which explains the concepts)
because these are implementation potholes, not conceptual trade-offs.

## Grafana Cloud auth method: `grafana_assume_role`, not `default` + `assumeRoleArn`

The CloudWatch data source has several `authType` values. The one that needs
only an `externalId` (no long-lived AWS keys) is its own distinct value,
`"grafana_assume_role"` — not `"default"` combined with `assumeRoleArn` (that
combination is plain AWS-SDK-default-then-assume-role, a different method),
and not `"arn"` (not a real value at all). Grafana Cloud stacks don't have the
bare `"default"` AWS-SDK method in their `allowed_auth_providers` list, so
both wrong values failed identically with `trying to use non-allowed auth
method default`.

Confirmed by reading the `@grafana/aws-sdk` package's actual auth type enum:
`keys`, `credentials`, `default`, `ec2_iam_role`, `arn`, `grafana_assume_role`.

This was the root cause of every panel showing "No data" for a long stretch,
despite the IAM role, trust policy, and OAM link all being individually
correct — the *data source itself* wasn't even authenticating.

See `terraform/grafana.tf`, `grafana_data_source.cloudwatch`.

## OAM discovery needs its own IAM permissions beyond `CloudWatchReadOnlyAccess`

`CloudWatchReadOnlyAccess` alone is not enough for Grafana's CloudWatch data
source to surface metrics shared via an OAM link. It additionally needs
`oam:ListSinks` / `oam:ListAttachedLinks` to discover and traverse the
cross-account link. Without this, the OAM link exists and works fine in the
AWS Console, but Grafana has no way to know about it — panels querying the
monitoring account silently omit the linked account's metrics with no error.

See `terraform/grafana.tf`, `aws_iam_role_policy.grafana_cloudwatch_read_oam`.

## `dimensions = {}` needs `matchExact = false`, or the query matches nothing

`matchExact` defaults to `true`, which requires an *exact*-match dimension
search. Combined with `dimensions = {}`, that matches nothing at all — an
empty dimension set is not "any dimensions," it's "these exact zero
dimensions." Setting `matchExact = false` switches CloudWatch to a wildcard
`SEARCH()` across all series, which is what actually returns data for a
namespace/metric without pinning to one instance ID up front.

## CloudWatch's OTLP→Prometheus metric naming isn't a mechanical lowercase-and-underscore transform

Expected `aws_ec2_networkin_sum` (metric name `NetworkIn` lowercased,
underscored). The real name Grafana Cloud's Mimir stores is
`aws_ec2_network_in_sum` — CloudWatch's OTLP conversion inserts an underscore
between "network" and the direction word specifically, which isn't
predictable from the metric name alone. Found by listing the actual
`__name__` label values present in Mimir
(`/api/v1/label/__name__/values?match[]={__name__=~"aws_ec2.*"}`) rather than
guessing the naming convention.

## Grafana Cloud's Prometheus query API needs a `/api/prom` path suffix

`data.grafana_cloud_stack.this.prometheus_url` returns just the host, e.g.
`https://prometheus-prod-65-prod-eu-west-2.grafana.net`. Using that directly
as a Grafana `prometheus` data source's `url` 404s on every query path — the
Mimir-backed Prometheus-compatible API is actually served under a required
`/api/prom` prefix. Found by comparing against the stack's own pre-provisioned
default `grafanacloud-<slug>-prom` data source, whose `url` already carried
that suffix, and confirming the datasource health check flips from
`HTTP 400: 404 Not Found` to healthy once the suffix is added.

## Grafana Cloud's CloudWatch Metric Streams ingest endpoint isn't `otlp_url`

The obvious guess — the stack's `otlp_url`
(`otlp-gateway-<region>.grafana.net`) — rejects every credential with
"invalid"/"no credentials provided" errors, confirmed via direct `curl`
against both Basic Auth and the `X-Amz-Firehose-Access-Key` header. The real
ingest host is a distinct `aws-metric-streams-<cell>.<domain>` origin, derived
from the *Prometheus remote-write* host, not the OTLP host: take the numeric
cell id (the `prod-<N>` segment right after `prometheus-`) and the domain
after the first dot. E.g. `prometheus_url`
`https://prometheus-prod-65-prod-eu-west-2.grafana.net` → ingest host
`https://aws-metric-streams-prod-65.grafana.net`.

Also: Firehose's `http_endpoint_configuration.access_key` is delivered via the
`X-Amz-Firehose-Access-Key` header, not as an `Authorization: Basic` value —
Basic Auth fails with "no credentials provided" against *any* candidate host,
including the correct one, which made this look like a wrong-host problem for
longer than it should have.

See `terraform/grafana.tf`, the `grafana_metric_streams_endpoint` local.

## `metrics:write` alone isn't enough for the Metric Streams access policy

The `aws-metrics` ingest path specifically returns "authentication error: no
credentials provided" with a token scoped to `metrics:write` only — even
though the *same* token authenticates fine against the standard Prometheus
remote-write endpoint. Grafana's own Terraform Provider Authentication docs
list `integration-management:read/write` alongside `stacks:read` as required
scopes in this area; adding those three scopes alongside `metrics:write`
resolved it.

## The CloudWatch query *editor* silently refuses to run queries missing certain fields — with zero error, in either the console or network tab

This was the most expensive gotcha to diagnose. Dashboards built by writing
raw dashboard JSON via Terraform (rather than through Grafana's UI query
editor) had CloudWatch panels stuck on "No data" in the live browser, with:

- **No JS error** in the browser console.
- **No `/api/ds/query` network request firing at all** for the panel — not a
  failed request, no request.
- Meanwhile, calling `/api/ds/query` directly with the *exact same query*
  returned real data immediately, every time, no matter how the call was
  shaped (different `intervalMs`, `maxDataPoints`, etc. all worked).

This ruled out: the datasource being unhealthy (it wasn't — health checks
passed), a caching layer (varying query params didn't change the outcome),
stale browser cache (survived hard refresh), and the CloudWatch plugin being
disabled (a red herring — its `enabled: false` API field turned out to be
meaningless for bundled/core plugins; Prometheus, which worked fine, reported
the same `false`).

The actual fix: manually re-picking the datasource in the panel editor UI and
saving, then diffing the resulting dashboard JSON against what Terraform had
generated. The rescued version added exactly four fields to the query target
that Terraform's hand-built JSON didn't have:

```
accountId        = "all"
metricEditorMode = 0
metricQueryType  = 0
queryMode        = "Metrics"
```

The backend plugin runs a CloudWatch query fine without these — they're
purely consumed by the frontend query editor to decide *how* to build and
fire the request. Missing them, the editor apparently decides there's nothing
valid to run and never dispatches anything, with no error surfaced anywhere.
`accountId = "all"` additionally has real semantic meaning for OAM dashboards
specifically: it's what tells the editor to include OAM-shared metrics from
linked accounts, not just the local account's own.

**Takeaway:** dashboard JSON generated by hand (Terraform, raw API calls, etc.)
for data sources with a rich visual query editor (CloudWatch here) may be
*backend-valid* but *frontend-inert*. When a hand-built panel shows "No data"
with a healthy datasource and a working direct API call, suspect missing
editor-only fields before suspecting auth, data, or caching — and the fastest
way to find them is to let the real UI resave the panel and diff the JSON.

## A provider-less resource silently lands in the wrong AWS account

`aws_iam_role.cross_account_sharing` in `terraform/cross-account-console.tf`
was declared without a `provider` argument, meaning it used the module's
default (un-aliased) provider — which per `providers.tf` targets the org's
**management account**, not any of the 3 demo accounts. Terraform applied
without error and the role existed, so nothing looked broken; it just wasn't
anywhere a source account (`account_b`, `account_c`) could ever assume into.

Symptom: the CloudWatch console's cross-account/cross-region metrics browser,
logged in as the monitoring account, only ever showed `account_a`'s own
region (`us-east-1`) — `account_c`'s `us-west-2` metrics never appeared, with
no error anywhere, because there was no sharing role in `account_c` (or
`account_b`) to assume in the first place.

Fixed by splitting the single resource into `cross_account_sharing_b` /
`cross_account_sharing_c`, each with an explicit `provider = aws.account_b` /
`aws.account_c`. **Takeaway:** in a multi-provider Terraform config, a
resource missing an explicit `provider` doesn't fail — it silently uses
whatever the default provider happens to be, which may not be any account you
intended.

## Correct IAM roles on both sides are not sufficient — the monitoring account still needs to explicitly discover/link each source account

After fixing the provider bug above, `account_b` showed up fine in the
monitoring account's cross-account console view, but `account_c` never did —
despite both source accounts having byte-for-byte identical
`CloudWatch-CrossAccountSharingRole` trust policies and attachments. Checked
CloudTrail in both `account_c` and `account_a` for any `AssumeRole` activity
between them: **zero** attempts, in either direction, over an hour spanning
well after the role existed. This ruled out a permissions/SCP denial (which
would show up as a *denied* CloudTrail event, not a total absence of any
attempt) — `cloudwatch-crossaccount.amazonaws.com` simply never tried to
reach `account_c`.

Root cause: this legacy feature's account list is **service-side state that
the IAM trust policy alone does not populate**. The trust policy only
determines whether an assume-role *would* succeed if attempted — something
still has to register `account_c` with the monitoring account's "Monitoring
account configuration" so CloudWatch knows to attempt it in the first place.
That registration step has no Terraform resource in the `hashicorp/aws`
provider (only OAM's sink/link model does) and no CLI verb either — it's a
console-only, click-through flow (CloudWatch → Settings → Monitoring account
configuration → add/link account). `account_b` most likely got linked this
way at some earlier point during development and was never re-derived from
Terraform.

**Takeaway:** for this specific approach, "the IAM roles are correct" and
"the console will show the data" are two different claims — don't assume the
second follows from the first. And it's a real, permanent limitation of this
approach, not just a demo gap: unlike OAM (fully declarative, sink + link),
this feature's account-to-account linking has no infrastructure-as-code
story at all.

## An org-wide SCP region restriction can deny a call with no obvious connection to region

Hit `cloudwatch:ListDashboards` denied with `explicit deny in a service
control policy` while browsing the merged cross-account console view. The SCP
(`RestrictRegions`) denies any request whose `aws:RequestedRegion` isn't in an
allow-list (`eu-central-1`, `us-west-2`, `us-east-1`) — the deny had nothing
to do with IAM permissions or the cross-account role chain at all. The
console's region selector was simply set to a region outside that allow-list
at the time. Switching it back to `us-east-1` resolved it immediately.
**Takeaway:** an explicit-deny SCP error can look identical to a missing-IAM-
permission error; check the requested region against any org-level region
restriction before debugging the role/policy chain.

## AWS credentials in an agent/CI session are not one shared thing

Grafana MCP access and AWS CLI/Terraform access are two completely unrelated
credential stores; having a working Grafana session implies nothing about AWS
access. Separately, `~/.aws/config` can hold several *unrelated* AWS
Organizations (payer accounts) side by side — a profile like
`AdministratorAccess-693103756206` only sees that org's own linked accounts.
The 3 demo accounts (`account_a/b/c`) turned out to belong to that org as
member accounts reachable only via
`sts assume-role --role-arn arn:aws:iam::<id>:role/OrganizationAccountAccessRole`,
not via any directly-named profile — `aws sts get-caller-identity` under the
plain profile alone doesn't reach them.
