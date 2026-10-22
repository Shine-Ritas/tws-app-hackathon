data "aws_partition" "current" {}

locals {
  eks_host_access_policies = {
    bastion = "AmazonEKSClusterAdminPolicy"
    jenkins = "AmazonEKSEditPolicy"
  }
}

# Preserve the existing access-entry addresses when upgrading this repository.
# If the old hardcoded principal differs from the deployer, Terraform replaces it.
moved {
  from = module.eks.aws_eks_access_entry.this["example"]
  to   = module.eks.aws_eks_access_entry.this["cluster_creator"]
}

moved {
  from = module.eks.aws_eks_access_policy_association.this["example_example"]
  to   = module.eks.aws_eks_access_policy_association.this["cluster_creator_admin"]
}

data "aws_iam_policy_document" "eks_hosts_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "eks_hosts" {
  for_each = local.eks_host_access_policies

  name_prefix        = "${local.name}-${each.key}-"
  assume_role_policy = data.aws_iam_policy_document.eks_hosts_assume_role.json
  tags               = local.tags
}

# update-kubeconfig needs AWS API permission in addition to Kubernetes access.
data "aws_iam_policy_document" "eks_hosts_describe_cluster" {
  statement {
    actions   = ["eks:DescribeCluster"]
    resources = [module.eks.cluster_arn]
  }
}

resource "aws_iam_role_policy" "eks_hosts_describe_cluster" {
  for_each = local.eks_host_access_policies

  name   = "describe-eks-cluster"
  role   = aws_iam_role.eks_hosts[each.key].id
  policy = data.aws_iam_policy_document.eks_hosts_describe_cluster.json
}

resource "aws_iam_instance_profile" "eks_hosts" {
  for_each = local.eks_host_access_policies

  name_prefix = "${local.name}-${each.key}-"
  role        = aws_iam_role.eks_hosts[each.key].name
  tags        = local.tags
}
