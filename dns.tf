# ---------------------------------------------------------------------------
# Public DNS and TLS — Phase 4
# ---------------------------------------------------------------------------
# Everything here is gated on var.enable_dns and is OFF by default.
#
# Why off: as of this writing the only hosted zone in the account is
# elbeetest.com, and that domain is not registered -- `whois` returns "No match"
# and the .com servers return SOA rather than a delegation. The zone exists, but
# nothing on the public internet resolves it.
#
# That is not a cosmetic problem. ACM validates a DNS-validated certificate by
# resolving the validation CNAME over PUBLIC DNS. On an undelegated zone the
# record is created, ACM never sees it, the certificate sits in
# PENDING_VALIDATION, and aws_acm_certificate_validation blocks the apply until
# it times out. The stranded _39197f6e... CNAME already sitting in that zone is
# the fossil of exactly this.
#
# To enable: set enable_dns = true and domain_name / hosted_zone_id to a domain
# that actually resolves, then `make apply`.

locals {
  app_fqdn = var.enable_dns ? "${var.app_subdomain}.${var.domain_name}" : ""
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

  zone_id         = var.hosted_zone_id
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

  # Without this, nothing orders validation after registration -- Terraform
  # would happily ask ACM to validate a domain that does not exist yet.
  depends_on = [aws_route53domains_domain.this]

  timeouts {
    # Two different situations, two different sensible waits.
    #
    # Domain already registered: fail in 10 minutes. If validation has not
    # completed by then the cause is almost always delegation, and a fast
    # failure says more than a long hang.
    #
    # Domain registered in this same apply: allow 45. A brand-new registration
    # has to reach the registry and propagate before ACM's resolver can see the
    # validation record, and that is legitimately slow.
    create = var.register_domain ? "45m" : "10m"
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
  external_dns_hosted_zone_arns = ["arn:aws:route53:::hostedzone/${var.hosted_zone_id}"]

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
