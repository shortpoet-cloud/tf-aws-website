mock_provider "aws" {}
mock_provider "cloudflare" {}

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

run "baseline_keeps_acls_off_and_versioning_unchanged" {
  command = plan

  assert {
    condition     = module.bucket_baseline.allow_public_policy && !module.bucket_baseline.versioning_enabled
    error_message = "The website bucket allows its public-read policy and stays unversioned."
  }
}
