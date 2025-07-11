# VM-Series Quick Lab
This is a relatively simple Terraform script that can be used to quickly spin up a Palo Alto Networks VM-Series firewall on AWS with an Ubuntu EC2 instance behind it for testing purposes.

## Requirements

1. Terraform must be installed
2. Must have your `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` set as environment variables
3. AWS CLI must be installed (required for Terraform to work)
4. A valid keypair in AWS

## How to use

After running the proverbial `terraform init` and `terraform plan` simply run the below in your working directory:

`terraform apply -var="aws_region=<your-region-of-choice>"`

The script will then create all the necessary infrastructure from the VPC onward.
