resource "random_pet" "bucket_name" {
  length    = 3
  separator = "-"
}

module "s3" {
  source                  = "../../modules/s3_bucket"
  site_domain_bucket_name = random_pet.bucket_name.id
  tags = {
    Terraform = "true"
    Project   = "tf-aws-website/examples/bucket"
  }
}
