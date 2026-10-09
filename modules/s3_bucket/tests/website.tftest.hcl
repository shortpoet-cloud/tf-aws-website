mock_provider "aws" {
  override_resource {
    target          = aws_s3_bucket.site
    override_during = plan
    values = {
      arn = "arn:aws:s3:::example.com"
    }
  }

  mock_data "aws_iam_user" {
    defaults = {
      user_id = "AIDAADMINISTRATOR"
    }
  }

  mock_data "aws_iam_role" {
    defaults = {
      unique_id = "AROATERRAFORMADMIN"
    }
  }
}

mock_provider "cloudflare" {
  mock_data "cloudflare_ip_ranges" {
    defaults = {
      ipv4_cidr_blocks = ["173.245.48.0/20"]
      ipv6_cidr_blocks = ["2400:cb00::/32"]
    }
  }
}

variables {
  site_domain_bucket_name = "example.com"
}

run "site_serves_index_and_error_documents" {
  command = plan

  assert {
    condition = (
      one(aws_s3_bucket_website_configuration.site.index_document).suffix == "index.html"
      && one(aws_s3_bucket_website_configuration.site.error_document).key == "index.html"
      && length(aws_s3_bucket_website_configuration.site.redirect_all_requests_to) == 0
    )
    error_message = "A site bucket serves index.html for both documents and does not redirect."
  }
}

run "redirect_bucket_has_one_redirect_only_configuration" {
  command = plan

  variables {
    site_domain_bucket_name  = "www.example.com"
    redirect_all_requests_to = "example.com"
  }

  assert {
    condition = (
      one(aws_s3_bucket_website_configuration.site.redirect_all_requests_to).host_name == "example.com"
      && length(aws_s3_bucket_website_configuration.site.index_document) == 0
      && length(aws_s3_bucket_website_configuration.site.error_document) == 0
    )
    error_message = "A redirect bucket's one website configuration only redirects."
  }
}

run "public_reads_come_only_from_cloudflare" {
  command = plan

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.site.policy).Statement :
      statement.Effect == "Allow"
      && statement.Action == "s3:GetObject"
      && statement.Resource == ["arn:aws:s3:::example.com/*"]
      && statement.Condition == { IpAddress = { "aws:SourceIp" = ["173.245.48.0/20", "2400:cb00::/32"] } }
    ])
    error_message = "Public GetObject must be allowed only from the Cloudflare IP ranges."
  }
}

run "everything_else_is_denied_except_the_admins" {
  command = plan

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.site.policy).Statement :
      statement.Effect == "Deny"
      && statement.Action == "s3:*"
      && statement.Resource == ["arn:aws:s3:::example.com", "arn:aws:s3:::example.com/*"]
      && statement.Condition == {
        NotIpAddress  = { "aws:SourceIp" = ["173.245.48.0/20", "2400:cb00::/32"] }
        StringNotLike = { "aws:userId" = ["AIDAADMINISTRATOR", "AROATERRAFORMADMIN:*"] }
      }
    ])
    error_message = "Requests from outside Cloudflare must be denied, exempting only the Administrator user and terraform-admin role sessions."
  }
}
