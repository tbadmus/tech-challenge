# Optional — Transit Gateway (hub and spoke)

These modules are **not part of the main deployment path.** ADR-0001 removed the
two-VPC topology they supported, and the root module no longer references them.

They are kept because the pattern is genuinely worth learning — it is how
multi-account estates and on-premises connectivity actually work — and because
seeing *why* it was the wrong tool for a single-account demo teaches more than
never meeting it.

## What was here before

The original stack ran two VPCs joined by a Transit Gateway:

```
Pod (VPC2, 172.31/16)  ->  TGW  ->  NAT (VPC1, 10.0/16)  ->  IGW  ->  Internet
```

A pod reaching the internet left its VPC, crossed the gateway, and hairpinned
out through the *other* VPC's NAT gateway. The stated goal was to keep worker
nodes off the public internet.

## Why it was the wrong tool here

Containment comes from **subnet routing**, not from a VPC boundary. A node in a
private subnet has no public IP and no inbound path whether or not that subnet
sits in its own VPC. The split added a hop without adding isolation, and cost:

| Cost | Detail |
|---|---|
| ~$70–75/month | Two attachments at ~$0.05/hour, before data processing at $0.02/GB |
| One unmanaged resource | See `routes.sh` below |
| A hidden dependency graph | `module.eks2` needed a five-entry `depends_on` to sequence around infrastructure Terraform could not see |

## `routes.sh` — the interesting failure

Read this file. It is the most instructive thing in the directory.

```bash
aws ec2 create-transit-gateway-route ... || true
```

The TGW default-route-table entry was created by the AWS CLI, invoked from a
`null_resource` with a `local-exec` provisioner, with every error swallowed by
`|| true`. The node group could not register without that route — yet the route
was:

- **not in state**, so it never appeared in a plan;
- **never recreated**, because the `triggers` block hashed the *script file*,
  not the infrastructure the route depended on;
- **never destroyed**, so `terraform destroy` left it behind;
- **silent on failure**, because of `|| true`.

The lesson is not "avoid `null_resource`". It is that the moment you shell out,
you leave the model — and everything Terraform gives you (planning, drift
detection, dependency ordering, teardown) stops applying to that resource. If a
provider has a resource for the thing, use it:

```hcl
resource "aws_ec2_transit_gateway_route" "default" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_route_table_id = aws_ec2_transit_gateway.main.association_default_route_table_id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke.id
}
```

## When a Transit Gateway *is* right

- More than two VPCs needing any-to-any routing. Peering is not transitive, so
  *n* VPCs need *n(n−1)/2* peerings; a TGW needs *n* attachments.
- Connecting VPCs across **different AWS accounts**, shared via RAM.
- Terminating Direct Connect or Site-to-Site VPN once and reaching every VPC
  through it.
- A central inspection VPC that all east–west traffic must traverse.

None of those applied to a single-account demo cluster.

## Using these modules

They were written for provider v5 and have not been migrated or tested against
v6. Treat them as reading material; validate before relying on them.

```hcl
module "tgw" {
  source   = "./optional/tgw/gateway"
  tgw_name = "hub"
}

module "tgw_attachment" {
  source     = "./optional/tgw/attachment"
  for_each   = var.spokes
  vpc_id     = each.value.vpc_id
  subnet_ids = each.value.subnet_ids
  tgw_id     = module.tgw.id
  name       = each.key
}

module "tgw_route" {
  source                 = "./optional/tgw/route"
  route_table_id         = var.spoke_route_table_id
  destination_cidr_block = "10.0.0.0/8"
  tgw_id                 = module.tgw.id
}
```

Note `attachment/outputs.tf` and `route/outputs.tf` are empty files — a module
that exposes nothing cannot be composed, which is its own small lesson.
