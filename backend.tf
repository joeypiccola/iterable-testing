terraform {
  backend "s3" {
    bucket         = "iterable-tfstate-20220603040326114200000001"
    key            = "iterable.tfstate"
    region         = "us-east-1"
    dynamodb_table = "iterable_tfstate_lock"
  }
}
