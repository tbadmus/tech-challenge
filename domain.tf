# ---------------------------------------------------------------------------
# Domain registration — Phase 4, gated on var.register_domain
# ---------------------------------------------------------------------------
# Terraform CAN register a domain: aws_route53domains_domain takes a name, a
# duration and the three contact blocks. Registering here rather than by hand
# keeps the no-ClickOps property intact all the way down to the domain itself.
#
# Three things to understand before enabling this.
#
# 1. IT SPENDS MONEY, and the charge is not refundable. A .com is currently
#    $16.00/year registration and $16.00/year renewal. `terraform destroy` does
#    NOT unregister the domain -- registrations cannot be cancelled, so destroy
#    only drops the resource from state while the registration and its renewal
#    obligation continue. Set auto_renew deliberately.
#
# 2. NAMESERVERS. Registering a domain through Route53 normally creates a fresh
#    hosted zone and delegates to it. A hosted zone for elbeetest.com already
#    exists (Z06069972H7T90FAW0B2Q), so letting that happen would produce a
#    SECOND zone, point the domain at it, and silently orphan the first --
#    including the records this stack manages. Setting name_server explicitly to
#    the existing zone's delegation set is what prevents that.
#
# 3. CONTACT DETAILS ARE REAL AND PUBLIC-ADJACENT. They go to the registrar and,
#    without privacy protection, into WHOIS. They are marked sensitive and are
#    expected in a gitignored tfvars file -- never committed.

resource "aws_route53domains_domain" "this" {
  count = var.register_domain ? 1 : 0

  # Route53 Domains has its API in us-east-1 only, wherever else this deploys.
  provider = aws.us_east_1

  domain_name       = var.domain_name
  duration_in_years = var.domain_duration_years

  # Off by default. A demo domain that quietly renews every year is a small
  # recurring bill nobody remembers agreeing to.
  auto_renew = var.domain_auto_renew

  # Prevents an unauthorised transfer away from this account.
  transfer_lock = true

  # Delegate to the hosted zone that already exists rather than a new one.
  # See note 2 above -- this is the line that stops the existing zone from
  # being orphaned.
  name_server = [for ns in var.domain_name_servers : { name = ns }]

  # WHOIS privacy on every contact. Without these, the address and phone number
  # below are published.
  registrant_privacy = true
  admin_privacy      = true
  tech_privacy       = true
  billing_privacy    = true

  registrant_contact {
    contact_type      = var.domain_contact.contact_type
    organization_name = var.domain_contact.organization_name
    first_name        = var.domain_contact.first_name
    last_name         = var.domain_contact.last_name
    address_line_1    = var.domain_contact.address_line_1
    city              = var.domain_contact.city
    state             = var.domain_contact.state
    country_code      = var.domain_contact.country_code
    zip_code          = var.domain_contact.zip_code
    phone_number      = var.domain_contact.phone_number
    email             = var.domain_contact.email
  }

  admin_contact {
    contact_type      = var.domain_contact.contact_type
    organization_name = var.domain_contact.organization_name
    first_name        = var.domain_contact.first_name
    last_name         = var.domain_contact.last_name
    address_line_1    = var.domain_contact.address_line_1
    city              = var.domain_contact.city
    state             = var.domain_contact.state
    country_code      = var.domain_contact.country_code
    zip_code          = var.domain_contact.zip_code
    phone_number      = var.domain_contact.phone_number
    email             = var.domain_contact.email
  }

  tech_contact {
    contact_type      = var.domain_contact.contact_type
    organization_name = var.domain_contact.organization_name
    first_name        = var.domain_contact.first_name
    last_name         = var.domain_contact.last_name
    address_line_1    = var.domain_contact.address_line_1
    city              = var.domain_contact.city
    state             = var.domain_contact.state
    country_code      = var.domain_contact.country_code
    zip_code          = var.domain_contact.zip_code
    phone_number      = var.domain_contact.phone_number
    email             = var.domain_contact.email
  }

  timeouts {
    # Registration is asynchronous; the registrar can take a while.
    create = "30m"
  }
}
