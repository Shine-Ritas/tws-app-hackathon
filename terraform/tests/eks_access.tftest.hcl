# All providers are mocked: these tests do not use AWS credentials or create
# infrastructure. Generate terra-key.pub as described in the setup instructions.
mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/deployer"
      user_id    = "TESTDEPLOYER"
    }
  }

  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::123456789012:user/deployer"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_ami" {
    defaults = {
      id = "ami-0123456789abcdef0"
    }
  }

  mock_data "aws_eks_addon_version" {
    defaults = {
      version = "v1.0.0-eksbuild.1"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-role"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock-policy"
    }
  }

  mock_resource "aws_eks_cluster" {
    defaults = {
      arn      = "arn:aws:eks:ap-southeast-1:123456789012:cluster/tws-eks-cluster"
      endpoint = "https://mock.eks.amazonaws.com"
      certificate_authority = [{
        data = "dGVzdA=="
      }]
      identity = [{
        oidc = [{ issuer = "https://oidc.eks.ap-southeast-1.amazonaws.com/id/EXAMPLE" }]
      }]
    }
  }
}

mock_provider "tls" {}
mock_provider "time" {}
mock_provider "cloudinit" {}
mock_provider "null" {}

# Keep networking and node-group implementation out of the access regression tests.
override_module {
  target = module.vpc
  outputs = {
    vpc_id          = "vpc-0123456789abcdef0"
    private_subnets = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    public_subnets  = ["subnet-0123456789abcdef2", "subnet-0123456789abcdef3"]
  }
}

override_module {
  target = module.eks.module.eks_managed_node_group["tws-demo-ng"]
  outputs = {
    node_group_id = "mock-node-group"
  }
}

override_module {
  target = module.eks.module.kms
  outputs = {
    key_arn = "arn:aws:kms:ap-southeast-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }
}

override_resource {
  target = aws_iam_role.eks_hosts["bastion"]
  values = {
    arn  = "arn:aws:iam::123456789012:role/test-bastion"
    name = "test-bastion"
  }
}

override_resource {
  target = aws_iam_role.eks_hosts["jenkins"]
  values = {
    arn  = "arn:aws:iam::123456789012:role/test-jenkins"
    name = "test-jenkins"
  }
}

run "iam_user_and_ec2_roles" {
  command = apply

  assert {
    condition     = module.eks.access_entries["cluster_creator"].principal_arn == "arn:aws:iam::123456789012:user/deployer"
    error_message = "The deploying IAM user must receive access instead of the original author's identity."
  }

  assert {
    condition     = endswith(module.eks.access_policy_associations["cluster_creator_admin"].policy_arn, "/AmazonEKSClusterAdminPolicy")
    error_message = "The deployer must receive cluster admin access."
  }

  assert {
    condition = (
      aws_instance.bastion_host.iam_instance_profile == aws_iam_instance_profile.eks_hosts["bastion"].name &&
      aws_iam_instance_profile.eks_hosts["bastion"].role == "test-bastion" &&
      module.eks.access_entries["bastion"].principal_arn == "arn:aws:iam::123456789012:role/test-bastion" &&
      endswith(module.eks.access_policy_associations["bastion_access"].policy_arn, "/AmazonEKSClusterAdminPolicy")
    )
    error_message = "The bastion must use its own instance role with cluster admin access."
  }

  assert {
    condition = (
      aws_instance.testinstance.iam_instance_profile == aws_iam_instance_profile.eks_hosts["jenkins"].name &&
      aws_iam_instance_profile.eks_hosts["jenkins"].role == "test-jenkins" &&
      module.eks.access_entries["jenkins"].principal_arn == "arn:aws:iam::123456789012:role/test-jenkins" &&
      endswith(module.eks.access_policy_associations["jenkins_access"].policy_arn, "/AmazonEKSEditPolicy")
    )
    error_message = "Jenkins must use its own role with application editing access."
  }
}

run "assumed_role_and_teammate" {
  command = apply

  override_data {
    target = module.eks.data.aws_caller_identity.current[0]
    values = {
      account_id = "210987654321"
      arn        = "arn:aws:sts::210987654321:assumed-role/DeploymentRole/test-session"
      user_id    = "TESTROLE:test-session"
    }
  }

  override_data {
    target = module.eks.data.aws_iam_session_context.current[0]
    values = {
      issuer_arn = "arn:aws:iam::210987654321:role/DeploymentRole"
    }
  }

  variables {
    eks_additional_admin_principals = {
      teammate = "arn:aws:iam::210987654321:role/PlatformTeam"
    }
  }

  assert {
    condition     = module.eks.access_entries["cluster_creator"].principal_arn == "arn:aws:iam::210987654321:role/DeploymentRole"
    error_message = "An assumed-role deployer must use its permanent IAM role ARN, including in another account."
  }

  assert {
    condition     = module.eks.access_entries["additional_teammate"].principal_arn == "arn:aws:iam::210987654321:role/PlatformTeam"
    error_message = "Additional teammate access must be configurable without editing the module."
  }
}

run "reject_session_arns" {
  command = plan

  variables {
    eks_additional_admin_principals = {
      invalid = "arn:aws:sts::123456789012:assumed-role/PlatformTeam/session"
    }
  }

  expect_failures = [var.eks_additional_admin_principals]
}

run "reject_duplicate_principals" {
  command = plan

  variables {
    eks_additional_admin_principals = {
      first  = "arn:aws:iam::123456789012:role/PlatformTeam"
      second = "arn:aws:iam::123456789012:role/PlatformTeam"
    }
  }

  expect_failures = [var.eks_additional_admin_principals]
}
