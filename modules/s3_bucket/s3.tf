data "cloudflare_ip_ranges" "cloudflare" {}
# data "aws_caller_identity" "current" {}
data "aws_iam_role" "terraform_admin" {
  name = "terraform-admin"
}
data "aws_iam_user" "admin" {
  user_name = "Administrator"
}
locals {
  # caller_arn           = "arn:aws:iam::${data.aws_caller_identity.current.account_id}"
  # TODO move to parent module as allowed ips
  cloudflare_ip_ranges = concat(data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks, data.cloudflare_ip_ranges.cloudflare.ipv6_cidr_blocks)
  redirects            = var.redirect_all_requests_to != null
  tags = merge(
    {
      Name = var.site_domain_bucket_name
    },
    var.tags,
  )
}

resource "aws_s3_bucket" "site" {
  bucket = var.site_domain_bucket_name
  # acl    = "private"
  tags = local.tags
}

resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  # A bucket has one website configuration: either a redirect, or the index and
  # error documents (they conflict). Two resources on one bucket fought each
  # other on every plan.
  dynamic "redirect_all_requests_to" {
    for_each = local.redirects ? [var.redirect_all_requests_to] : []
    content {
      host_name = redirect_all_requests_to.value
    }
  }

  dynamic "index_document" {
    for_each = local.redirects ? [] : ["index.html"]
    content {
      suffix = index_document.value
    }
  }

  dynamic "error_document" {
    for_each = local.redirects ? [] : ["index.html"]
    content {
      key = error_document.value
    }
  }

  # routing_rules = jsonencode([
  #   {
  #     Redirect = {
  #       ReplaceKeyPrefixWith = "/"
  #       HttpRedirectCode     = "301"
  #     }
  #     Condition = {
  #       KeyPrefixEquals = "index.html"
  #     }
  #   },
  #   {
  #     Redirect = {
  #       ReplaceKeyPrefixWith = ""
  #       HttpRedirectCode     = "301"
  #     }
  #     Condition = {
  #       KeyPrefixEquals = "docs/"
  #     }
  #   },
  # ])

}

resource "aws_s3_bucket_cors_configuration" "example" {
  bucket = aws_s3_bucket.site.id

  cors_rule {
    # allowed_headers = ["*"]
    # allowed_methods = ["PUT", "POST"]
    # allowed_origins = ["https://s3-website-test.hashicorp.com"]
    # expose_headers  = ["ETag"]
    # max_age_seconds = 3000
    allowed_headers = ["Authorization", "Content-Length"]
    allowed_methods = ["GET", "POST"]
    allowed_origins = ["https://www.${var.site_domain_bucket_name}"]
    max_age_seconds = 3000
  }

  cors_rule {
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
  }
}


module "bucket_baseline" {
  source = "git::ssh://git@github.com/shortpoet-cloud/tf-aws-s3.git//modules/bucket_baseline?ref=v0.1.0"

  bucket = aws_s3_bucket.site.id
  # Website objects are replaced on every deploy; versioning would keep each
  # old build. The policy grants public reads (Cloudflare IPs only).
  versioning_enabled  = false
  allow_public_policy = true
}

# The redirect now lives in the one website configuration; forget the second
# resource without deleting the bucket's website configuration.
removed {
  from = aws_s3_bucket_website_configuration.redirect

  lifecycle {
    destroy = false
  }
}

# Ownership is BucketOwnerEnforced, so ACLs no longer apply. Forget the ACL
# without touching the bucket.
removed {
  from = aws_s3_bucket_acl.site

  lifecycle {
    destroy = false
  }
}


locals {
  public_read_get_object = {
    Sid       = "PublicReadGetObject"
    Effect    = "Allow"
    Principal = "*"
    Action    = "s3:GetObject"
    Resource = [
      "${aws_s3_bucket.site.arn}/*",
    ],
    # Condition = {
    #   StringEquals = {
    #     "aws:Referer" = [
    #       "https://${var.site_domain}/*",
    #       "https://${var.site_domain}",
    #     ]
    #   }
    # }
    Condition = {
      IpAddress = {
        "aws:SourceIp" = local.cloudflare_ip_ranges
      }
    }
  }
  restrict_to_cloudflare_ips = {
    Sid    = "RestrictToCloudflareIPs"
    Effect = "Deny"
    Action = "s3:*"
    Resource = [
      aws_s3_bucket.site.arn,
      "${aws_s3_bucket.site.arn}/*",
    ]
    # NotPrincipal = {
    #   AWS = [
    #     "${local.caller_arn}:root",
    #     "${local.caller_arn}:user/Administrator",
    #   ]
    # }
    Principal = "*"
    Condition = {
      NotIpAddress = {
        "aws:SourceIp" = local.cloudflare_ip_ranges
      },
      StringNotLike = {
        "aws:userId" = [
          data.aws_iam_user.admin.user_id,
          "${data.aws_iam_role.terraform_admin.unique_id}:*",
        ]
      }
    }
  }

}
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.public_read_get_object,
      local.restrict_to_cloudflare_ips,
    ]
  })

  depends_on = [module.bucket_baseline]
}
