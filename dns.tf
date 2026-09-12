# ---------------------------------------------------------------------------
# Public DNS and TLS — ADR-0007
# ---------------------------------------------------------------------------
# Gated on var.enable_dns, off by default.
#
# This stack expects a domain that ALREADY EXISTS and is publicly resolvable,
# with a Route53 hosted zone in this account. It deliberately does not register
# domains: registration spends money on an implicit code path, is irreversible
# (registrations cannot be cancelled), and needs contact details that cannot
# sensibly be defaulted. Bring your own domain.
#
# The requirement that it be PUBLICLY RESOLVABLE is not pedantry. ACM validates
# a DNS-validated certificate by resolving the validation CNAME over public
# DNS. Point this at a zone whose domain is not delegated and the record is
# written, ACM never sees it, and aws_acm_certificate_validation blocks until it
# times out.
#
# Supply either hosted_zone_id (exact) or just domain_name (looked up by name,
# which is what makes this portable -- zone IDs differ in every account).

# Look the zone up by name unless an explicit ID was given. Erroring here when
# the zone is absent is correct: enable_dns is an assertion that it exists.
data "aws_route53_zone" "this" {
  count = var.enable_dns && var.hosted_zone_id == "" ? 1 : 0

  name         = var.domain_name
  private_zone = false
}

locals {
  app_fqdn = var.enable_dns ? "${var.app_subdomain}.${var.domain_name}" : ""

  zone_id = var.enable_dns ? (
    var.hosted_zone_id != "" ? var.hosted_zone_id : data.aws_route53_zone.this[0].zone_id
  ) : ""
}

# --- Certificate -----------------------------------------------------------

resource "aws_acm_certificate" "app" {
  count = var.enable_dns ? 1 : 0

  domain_name       = local.app_fqdn
  validation_method = "DNS"

  # Replace before destroying, so a certificate rotation never leaves the
  # listener without one.
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = local.app_fqdn })
}

resource "aws_route53_record" "app_cert_validation" {
  for_each = var.enable_dns ? {
    for o in aws_acm_certificate.app[0].domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      record = o.resource_record_value
      type   = o.resource_record_type
    }
  } : {}

  zone_id         = local.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "app" {
  count = var.enable_dns ? 1 : 0

  certificate_arn         = aws_acm_certificate.app[0].arn
  validation_record_fqdns = [for r in aws_route53_record.app_cert_validation : r.fqdn]

  timeouts {
    # Fail in 10 minutes rather than the 45-minute default. The domain is
    # required to be delegated already, so if validation has not completed by
    # then the cause is almost always that it is not -- and a fast failure says
    # far more than a long hang.
    create = "10m"
  }
}

# --- ExternalDNS -----------------------------------------------------------
# The ALB is created by the load balancer controller, not by Terraform, so
# Terraform cannot write an alias record for a hostname it never learns.
# ExternalDNS closes that loop from the other side: it watches Ingress objects
# and writes the records for the hostnames they declare.

module "external_dns_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  count = var.enable_dns ? 1 : 0

  name = "${local.name}-extdns"

  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = ["arn:aws:route53:::hostedzone/${local.zone_id}"]

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "external-dns"
    }
  }

  tags = local.common_tags
}

# The ExternalDNS Helm release lives in cluster-addons/ for the same reason as
# the load balancer controller: planning it requires reaching the cluster API.
