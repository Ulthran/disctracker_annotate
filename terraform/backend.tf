terraform {
  backend "s3" {
    bucket       = "ctbus-tfstates"
    key          = "disctracker_annotate/frontend.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
