------
V1.1 2022-06-07 UPDATED & ALTERNATIVE VERSION

This version updates terraform commands to fit the newest version of terraform.
Our projects did not need Healthcheck and though SSM, relevant lines were commented during code dev and untested.

This version proposes the below enhancements :
* Added to the initial setup a restore step, in case the terraforming needs to be done on an existing setup that went broken : your datas will be restored
* All setup files and logs are sent to the S3 bucket (pritunl request 2 commands to be performed on the machine and therefore to log in SSH. If you don't want the machine to have anything to do with SSH, comment the aws_key_name lines) and wait for the infos to get to the S3. Unfortunately pritunl now requests two commands and prompt for them, the second will be in error if you don't enter the secret-key within 10 minutes it is received.
* Since CentOS8 is now discontinued, Pritunl highly recommends the use of Oracle Linux (https://docs.pritunl.com/docs). The user_data template was filled accordingly. And to quote oracle (https://linux.oracle.com/switch/centos/) Oracle Linux is free, only the support costs money.


INITIAL README below (still accurate)
-------



# Overview
This module setups a VPN server for a VPC to connect to instances.

*Before you start to use the module you have to make sure you've created resources below*

* healthchecks.io account and cron entry for monitoring the backup script

After provisioning, don't forget to run commands below:

* **Pritunl setup**
  * `sudo pritunl setup-key`

# Input variables

* **aws_key_name:** SSH Key pair for VPN instance
* **vpc_id:** The VPC id
* **public_subnet_id:** One of the public subnets to create the instance
* **ami_id:** Amazon Linux AMI ID
* **instance_type:** Instance type of the VPN box (t2.small is mostly enough)
* **ebs_optimized:** Create EBS optimized EC2 instance. Default: `false`
* **whitelist:** List of office IP addresses that you can SSH and non-VPN connected users can reach temporary profile download pages
* **whitelist_http:** List of IP addresses that you can allow HTTP connections.
* **internal_cidrs:** List of CIDRs that will be whitelisted to access the VPN server internally.
* **tags:** Map of AWS Tag key and values
* **resource_name_prefix:** All the resources will be prefixed with the value of this variable
* **healthchecks_io_key:** Health check key for healthchecks.io
* **s3_bucket_name:** Optional bucket name for Pritunl backups

# Outputs
* **vpn_instance_private_ip_address:** Private IP address of the instance
* **vpn_public_ip_address:** EIP of the VPN box
* **vpn_management_ui:** URL for the management UI


# Usage

```
provider "aws" {
  region  = "eu-west-2"
}

module "app_pritunl" {
  source = "github.com/opsgang/terraform_pritunl?ref=2.0.0"

  aws_key_name         = "org-eu-west-2"
  vpc_id               = "${module.vpc.vpc_id}"
  public_subnet_id     = "${module.vpc.public_subnets[1]}"
  ami_id               = "ami-403e2524"
  instance_type        = "t2.nano"
  resource_name_prefix = "opsgang-pritunl"
  healthchecks_io_key  = "NNNNNNNN-NNNN-NNNN-NNNN-NNNNNNNNNNN"
  s3_bucket_name       = "i-want-to-override-generated-bucket-name"

  whitelist = [
    "8.8.8.8/32",
  ]

  tags {
    "role" = "vpn"
    "env"  = "prod"
  }
}
```

**P.S. :** Yes, AMI id is hardcoded! This module meant to be used in your VPC template. Presumably, no one wants to destroy the VPN instance and restore the configuration after `terraform apply` against to VPC. There is no harm to manage that manually and keep people working during the day.

*There will be wiki link about initial setup of Pritunl*
