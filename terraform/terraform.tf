terraform {
  backend "s3" {
    bucket       = "terraform-s3-backend-tws-hackathon-sg"
    key          = "backend-locking"
    region       = "ap-southeast-1"
    use_lockfile = true
  }
}