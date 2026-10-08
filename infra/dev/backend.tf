terraform {
  backend "s3" {
    bucket       = "sentinelpay-dev-tfstate-faith-2026"
    key          = "dev/network/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
