mock_provider "aws" {}

variables {
  bucket           = "example.com"
  base_folder_path = "tests/fixtures/site"
}

run "uploads_each_file_with_its_content_type" {
  command = plan

  assert {
    condition     = toset(keys(aws_s3_object.this)) == toset(["index.html", "_headers", "CNAME", "assets.v2/robots"])
    error_message = "Every file under base_folder_path is uploaded."
  }

  assert {
    condition     = aws_s3_object.this["index.html"].content_type == "text/html"
    error_message = "Content types come from mime.json by extension."
  }

  # assets.v2/robots has a dotted directory but no extension in its file name.
  assert {
    condition = alltrue([
      for key in ["_headers", "CNAME", "assets.v2/robots"] : aws_s3_object.this[key].content_type == "text/plain"
    ])
    error_message = "Files without an extension in their name are text/plain."
  }
}

run "objects_carry_no_acl" {
  command = plan

  # bucket_baseline sets BucketOwnerEnforced, which rejects any object ACL,
  # including "private". The provider computes acl, so a null one is unknown at
  # plan; assert the value the module passes it.
  assert {
    condition     = local.acl == null
    error_message = "Objects must not set an ACL on a BucketOwnerEnforced bucket."
  }
}
