aws eks --region ap-southeast-1 update-kubeconfig --name tws-eks-cluster

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
