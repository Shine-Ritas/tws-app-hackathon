# Terraform infrastructure

## Portable EKS access

Deploy with an IAM user or assumed IAM role permitted to create the infrastructure,
IAM roles, and EKS access entries. Do not deploy with AWS account root credentials.
The configuration discovers the deployer's identity and creates access entries
in the account being used. No author's account ID or IAM username is required.
Assumed-role sessions are resolved to their permanent IAM role ARN by the EKS
module. Use a consistent deployment identity for subsequent Terraform applies;
applying with a different identity changes the deployer admin entry.

Terraform manages these identities:

| Identity | Kubernetes access | AWS credentials |
| --- | --- | --- |
| Terraform deployer | Cluster admin | Your local AWS CLI login/profile |
| Bastion EC2 role | Cluster admin, including nodes and Helm/CRD administration | Automatic temporary EC2 credentials |
| Jenkins EC2 role | Edit application resources throughout the cluster; no node listing or cluster administration | Automatic temporary EC2 credentials |
| Optional additional administrators | Cluster admin | Their own AWS CLI login/profile |

Both EC2 roles also receive `eks:DescribeCluster` permission for this cluster so
`aws eks update-kubeconfig` can run. These roles do not grant Terraform provisioning
permissions, ECR access, or unrelated AWS service permissions. Use the bastion to
manage cluster-wide resources; Jenkins can use `kubectl get deployments -A` to
verify its application access, with `kubectl` installed on its build agent.

For a new deployment, configure the S3 backend bucket in `terraform.tf` to a
bucket you own. Generate the SSH public key expected by `ec2.tf`, authenticate
your local AWS CLI, and run from this directory:

```bash
terraform init
terraform plan
terraform apply
terraform output eks_host_role_arns
terraform output -raw eks_kubeconfig_command
```

After the apply and instance bootstrap finish, SSH into the bastion and run:

```bash
aws sts get-caller-identity
aws eks update-kubeconfig --region ap-southeast-1 --name tws-eks-cluster
kubectl get nodes
```

The identity should be the bastion's assumed IAM role. Do not run `aws configure`
on the bastion or Jenkins host: the AWS CLI obtains short-lived credentials from
the instance role automatically. EKS tokens are refreshed by the kubeconfig's
AWS CLI exec command. Each Linux account needs its own kubeconfig. For a Jenkins
job, configure it as the service user, for example:

```bash
sudo -u jenkins -H /snap/bin/aws eks update-kubeconfig \
  --region ap-southeast-1 --name tws-eks-cluster
```

The Kubernetes endpoint is private. A local administrator also needs VPC network
connectivity (for example, a VPN or a session on the bastion) to run `kubectl`.
Access entries do not change that network requirement. A clone deployed in a
separate AWS account gets its own deployer and EC2 roles; cloning the repository
does not grant access to somebody else's cluster.

### Additional administrators

For teammates accessing the same cluster, set a named map in your local
`terraform.tfvars` or pass it through your deployment environment:

```hcl
eks_additional_admin_principals = {
  platform_team = "arn:aws:iam::123456789012:role/PlatformTeam"
}
```

Replace the example ARN with an existing IAM user or role. Do not use an
`arn:...:sts::...:assumed-role/...` session ARN or repeat the deployer/EC2 roles
already managed by this configuration. Apply using the existing deployment
identity to grant the additional access. Teammates must authenticate as one of
those approved identities and create their kubeconfig before using `kubectl`.

### Existing deployments

Run `terraform plan` and `terraform apply` using credentials permitted to manage
IAM and EKS access entries. This attaches instance profiles to the existing EC2
hosts and updates access entries; changing access does not require rebuilding
the instances or the cluster. The migration blocks preserve the old access-entry
address when it already refers to the deployer; a different old principal is
replaced. Review any unrelated replacements in your plan before applying.

If you previously ran `aws configure` on EC2, stored credentials or exported
keys can override the new role. In an EC2 shell, use the instance role for that
session without deleting your old configuration:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_EC2_METADATA_DISABLED
export AWS_SHARED_CREDENTIALS_FILE=/dev/null
export AWS_CONFIG_FILE=/dev/null
aws sts get-caller-identity
aws eks update-kubeconfig --region ap-southeast-1 --name tws-eks-cluster
kubectl get nodes
```

Run the final node check on the bastion. To make the credential cleanup permanent,
remove obsolete keys/profile settings from the EC2 account's AWS configuration and
shell startup files. Check the Jenkins service account's files and job environment
separately. Replace any exposed access keys in IAM; the role-based setup does not
revoke existing keys. EKS/IAM changes can take a short time to propagate after apply.

References: [EKS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html),
[EC2 role credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-metadata.html).

### Validate access changes locally

With Terraform 1.7 or later, initialized providers/modules, and the SSH public key
from the setup instructions present, run:

```bash
terraform validate
terraform test -filter=tests/eks_access.tftest.hcl
```

The tests mock every provider and do not contact AWS or create infrastructure.
They cover IAM user and assumed-role deployers, EC2 instance-role access, teammate
administrators, and rejected session/duplicate ARNs.

## Jenkins EC2 bootstrap

`ec2.tf` supplies `install_tools.sh` as user data to `aws_instance.testinstance`
(tagged `Jenkins-Automate`). Cloud-init runs it as root on the instance's first
boot. Terraform creating the instance successfully does not mean the installation
script finished successfully.

The script uses the Jenkins 2026 repository signing key and Java 21, as described
in the [Jenkins installation guide](https://www.jenkins.io/doc/book/installing/linux/).
The old 2023 key causes `NO_PUBKEY 7198F4B714ABFC68`, preventing the Jenkins package
from being installed. `Unit jenkins.service could not be found` is a consequence
of the missing package. The Trivy legacy-keyring warning is separate from that
Jenkins error.

### Recover an existing instance

Updating the local user-data script and running `terraform apply` does not rerun
the bootstrap on an existing instance. Copy the corrected script to the Jenkins
instance and run it there. From the local `terraform` directory, substitute the
instance's reachable public IP and your SSH private key path:

```bash
scp -i /path/to/private-key install_tools.sh ubuntu@JENKINS_PUBLIC_IP:/tmp/install_tools.sh
ssh -i /path/to/private-key ubuntu@JENKINS_PUBLIC_IP
```

Then run on the instance:

```bash
# Wait for any first-boot provisioning to finish before running recovery.
sudo cloud-init status --wait
sudo bash /tmp/install_tools.sh
sudo systemctl status jenkins --no-pager
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

If cloud-init reports its earlier bootstrap failure, inspect its log, then run
the corrected script above. Open `http://JENKINS_PUBLIC_IP:8080` to complete Jenkins
setup. Reconnect your SSH session to pick up the Ubuntu user's Docker group.

### Inspect bootstrap failures

```bash
sudo cloud-init status --long
sudo tail -n 100 /var/log/cloud-init-output.log
sudo tail -n 100 /var/log/install-tools.log
sudo journalctl -u jenkins -n 100 --no-pager
```

`install-tools.log` is written by the corrected script. It stops on the first
error and logs the failed command. Fresh instances receive the corrected script
automatically; use the recovery steps above to preserve an existing instance.
