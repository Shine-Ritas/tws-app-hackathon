variable "aws_region" {
  description = "AWS region where resources will be provisioned"
  default     = "us-east-2"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  default     = "ami-085f9c64a9b75eed5"
}

variable "instance_type" {
  description = "Instance type for the EC2 instance"
  default     = "t3.medium"
}

variable "eks_additional_admin_principals" {
  description = "Optional named IAM user or role ARNs granted EKS cluster admin access. Use IAM role ARNs, not STS session ARNs. Do not repeat the Terraform deployer or EC2 host roles."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for arn in values(var.eks_additional_admin_principals) :
      can(regex("^arn:[a-z0-9-]+:iam::[0-9]{12}:(user|role)/.+$", arn))
    ])
    error_message = "Each principal must be an IAM user or role ARN; root and STS assumed-role session ARNs are not supported."
  }

  validation {
    condition     = length(distinct(values(var.eks_additional_admin_principals))) == length(var.eks_additional_admin_principals)
    error_message = "Each additional IAM principal must be listed only once."
  }
}

variable "my_enviroment" {
  description = "Instance type for the EC2 instance"
  default     = "dev"
}
