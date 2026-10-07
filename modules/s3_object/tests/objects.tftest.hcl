mock_provider "aws" {}

variables {
  bucket           = "example.com"
  base_folder_path = "tests/fixtures/site"
}

run "uploads_each_file_with_its_content_type" {
  command = plan

  assert {
    condition     = toset(keys(aws_s3_object.this)) == toset(["index.html", "_headers"])
    error_message = "Every file under base_folder_path is uploaded."
  }

  assert {
    condition     = aws_s3_object.this["index.html"].content_type == "text/html" && aws_s3_object.this["_headers"].content_type == "text/plain"
    error_message = "Content types come from mime.json, and files without an extension are text/plain."
  }
}
