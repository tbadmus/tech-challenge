# Observability

Logs and metrics come from the `amazon-cloudwatch-observability` EKS addon:
Fluent Bit as a DaemonSet for logs, the CloudWatch agent for Container Insights
metrics. It replaces the self-managed Elasticsearch/Fluentd/Kibana stack, which
is preserved with a full post-mortem in [`optional/efk/`](../optional/efk/).

## Where things land

| Log group | Contents |
|---|---|
| `/aws/containerinsights/<cluster>/application` | container stdout/stderr |
| `/aws/containerinsights/<cluster>/dataplane` | kubelet, containerd, kube-proxy |
| `/aws/containerinsights/<cluster>/host` | `/var/log/messages`, `secure`, `dmesg` |
| `/aws/containerinsights/<cluster>/performance` | Container Insights embedded metrics |
| `/aws/eks/<cluster>/cluster` | control plane audit / api / authenticator |

All are created by Terraform **before** the agent runs, specifically so
`retention_in_days` is set. Left to create them itself the agent uses *Never
expire*, and the logs bill forever — the same defect the review found in the
original control plane logging.

## The nested-JSON gotcha

The app logs one JSON object per line. Fluent Bit does **not** ship that object
directly: it wraps container output in the CRI envelope, so what arrives in
CloudWatch is

```json
{"time":"...","stream":"stdout","_p":"F","log":"{\"level\":\"info\",\"msg\":\"request\",...}"}
```

The application's own fields are a *string* inside `log`, not top-level fields.
Logs Insights will happily return rows while every field you actually wanted
comes back empty, which reads like "the logging is broken" when it is working
perfectly. Extract them with `parse`.

## Queries that work

**External requests only** — health checks from the ALB and kubelet dominate
the raw stream, and neither carries `X-Forwarded-For`, so filtering on `client`
isolates real traffic:

```
fields @timestamp, log
| filter log like /"msg":"request"/
| parse log '"path":"*"' as path
| parse log '"status":*,' as status
| parse log '"duration_ms":*,' as duration_ms
| parse log '"client":"*"' as client
| filter ispresent(client)
| sort @timestamp desc
| limit 50
```

**Errors and warnings:**

```
fields @timestamp, log
| filter log like /"level":"(warn|error)"/
| sort @timestamp desc
| limit 50
```

**Slowest requests:**

```
fields @timestamp, log
| filter log like /"msg":"request"/
| parse log '"path":"*"' as path
| parse log '"duration_ms":*,' as duration_ms
| sort duration_ms desc
| limit 20
```

Making these fields top-level instead would mean overriding the addon's
`containerLogs.fluentBit.config.extraFiles.application-log.conf` to enable
`Merge_Log`. That replaces the whole shipped config file, so it is a real
maintenance commitment; `parse` is the cheaper answer at this scale.

## Metrics

Container Insights publishes to the `ContainerInsights` CloudWatch namespace,
keyed on `ClusterName`. Console: **CloudWatch → Insights → Container Insights**.

`applicationSignals` is disabled deliberately. It defaults to **on**, provides
APM-style tracing, and is billed per trace and per observed service — outside
what this project set out to demonstrate. Turn it on in `observability.tf` if
you want it.

## A note on running a public demo

The ALB is internet-facing, so the application receives unsolicited traffic
from internet-wide scanners within minutes of going up. Real example from the
logs above, a client that is not the operator:

```
2026-09-11 01:17:35  /  200  0.81ms  client=43.157.149.188
```

That is normal and expected for anything on a public address, but it is worth
seeing in the logs once: it is why `/readyz` and `/healthz` should not leak
internal detail, and why the review objected to the API endpoint defaulting to
`0.0.0.0/0`.
