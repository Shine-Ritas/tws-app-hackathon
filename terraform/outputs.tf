output "region" {
  description = "The AWS region where resources are created"
  value       = local.region
}

output "vpc_id" {
  description = "The ID of the created VPC"
  value       = module.vpc.vpc_id
}


output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}


output "public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.testinstance.public_ip
}

output "eks_node_group_public_ips" {
  description = "Public IPs of the EKS node group instances"
  value       = data.aws_instances.eks_nodes.public_ips
}

output "eks_host_role_arns" {
  description = "IAM roles used automatically by the bastion and Jenkins EC2 instances"
  value       = { for name, role in aws_iam_role.eks_hosts : name => role.arn }
}

output "eks_kubeconfig_command" {
  description = "Run this on the bastion or another host with network access to the private EKS endpoint"
  value       = "aws eks update-kubeconfig --region ${local.region} --name ${module.eks.cluster_name}"
}
