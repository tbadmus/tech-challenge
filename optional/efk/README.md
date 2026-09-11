# Optional — the original self-managed EFK stack

Superseded by the `amazon-cloudwatch-observability` addon. Kept as reading
material, because the most useful thing about these manifests is *why* running
your own log store is a bigger commitment than it looks.

**Not applied by anything.** Do not `kubectl apply -f` this directory onto the
demo cluster without reading below first.

## What it was

Three raw manifests — Elasticsearch as a StatefulSet, Fluentd as a DaemonSet,
Kibana behind an internal LoadBalancer — applied by the Jenkins pipeline.

## What was wrong with it

### It could not have worked on a modern cluster

`elastic.yaml` declares a `volumeClaimTemplate` requesting 30Gi with **no
`storageClassName`**:

```yaml
volumeClaimTemplates:
- metadata:
    name: elasticsearch
  spec:
    accessModes: [ReadWriteOnce]
    resources:
      requests:
        storage: 30Gi
```

Since Kubernetes 1.23 the in-tree EBS provisioner is gone from EKS, and the
`aws-ebs-csi-driver` addon appeared nowhere in the original repository. On top
of that, EKS ships a `gp2` StorageClass that is **not marked default** —
verified against the live cluster during this modernization. So the PVC would
have sat `Pending` indefinitely and the pod would never have started, with
nothing in the pipeline reporting a failure.

Both halves are fixed now, in the replacement: the EBS CSI driver is an addon
with its own Pod Identity role, and `cluster-addons/` installs a **gp3** class
marked default.

### The password was written into the file

```groovy
sed -i -e "s%ELASTIC-PASSWORD%${ELASTIC}%g" logging/elastic.yaml
```

The Jenkins pipeline substituted a credential into all three tracked manifests
at build time. It then existed in plaintext in the workspace, in the applied
pod spec, and in anything archiving the workspace. Jenkins masks credentials in
console output; it does not mask them on disk.

It is also not idempotent: on a second run in a persistent workspace the
placeholder is already gone, so the substitution silently no-ops.

### Untagged and end-of-life images

```yaml
image: "ubuntu"                                              # no tag -> :latest
image: "docker.elastic.co/elasticsearch/elasticsearch:7.15.2"  # EOL
image: "docker.elastic.co/kibana/kibana:7.15.2"                # EOL
image: fluent/fluentd-kubernetes-daemonset:v1-debian-elasticsearch  # floating tag
```

The init container runs `chown` as `image: "ubuntu"` with no tag, so the build
is not reproducible and the content can change underneath you.

### One replica of a stateful datastore

`replicas: 1` on the Elasticsearch StatefulSet. A single node holding the only
copy of your logs, on a demo cluster that gets torn down — a log store that
loses its data on a node replacement is worse than no log store, because people
believe it.

There are also no resource requests or limits, so Elasticsearch competes freely
with the workloads it is meant to be observing.

## What replaced it, and the honest trade-off

The `amazon-cloudwatch-observability` addon: Fluent Bit as a DaemonSet shipping
container, host and dataplane logs to CloudWatch Logs, plus Container Insights
metrics. No StatefulSet, no PVC, no JVM to size, no cluster to patch, no
password to inject, and log retention set explicitly in Terraform rather than
defaulting to "forever".

What you give up is real and worth stating: CloudWatch Logs Insights is a
weaker query language than Elasticsearch's, and Kibana's visualisations have no
direct equivalent. For a demo cluster that is plainly the right trade. For a
team whose daily work is log analysis, it might not be — in which case the
current answer is OpenSearch Service (managed) rather than an Elasticsearch
StatefulSet you operate yourself.
