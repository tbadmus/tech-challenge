# cluster-addons — software that runs *inside* the cluster

A second Terraform root module, separate from the infrastructure root on
purpose. It holds everything configured through the Kubernetes API: the AWS
Load Balancer Controller, ExternalDNS, and the default StorageClass.

## Why it is separate

The `kubernetes` and `helm` providers authenticate against the cluster's API
endpoint, so `terraform plan` has to *reach* that endpoint — even to compute a
diff. ADR-0004 restricts the public endpoint to a CIDR allowlist, which means a
GitHub-hosted runner cannot reach it:

```
Error: Get "https://<id>.gr7.us-east-1.eks.amazonaws.com/apis/storage.k8s.io/v1/storageclasses/gp3":
       dial tcp 174.129.23.46:443: i/o timeout
```

That is not a bug in the allowlist. It is the allowlist working, and it is the
tension ADR-0004 named when it chose option B.

Keeping these resources in the infrastructure root would force one of three bad
answers: widen the allowlist to GitHub's published ranges (which is close to
allowing the internet), run every plan from a self-hosted runner (heavy, for
resources that change rarely), or leave CI unable to plan the stack at all.

Splitting them means the infrastructure root has no cluster-facing provider,
so it plans from anywhere — including a hosted runner with no network path to
the cluster.

There is a second, older reason. A provider configured from resources in the
same root module is fragile on teardown: `terraform destroy` can remove the
cluster while Terraform still needs to authenticate to it in order to delete the
Helm releases. Separate roots destroy in a defined order.

## Running it

Requires network access to the cluster API — so either an allowlisted IP, or
the SSM tunnel:

```bash
make tunnel ENV=dev            # in another shell, if your IP is not allowlisted
make addons-init  ENV=dev
make addons-apply ENV=dev
```

`make` derives the state bucket from the AWS account and generates the backend
config at init time, so there is nothing to edit and no committed backend file.

## Where the inputs come from

Cluster coordinates, the region, the Pod Identity role ARNs, and the DNS
settings are all read from the infrastructure root's state via
`terraform_remote_state`. That is a read-only dependency in one direction:
infrastructure knows nothing about addons, and nothing is restated in a second
tfvars file where the two could drift apart.
