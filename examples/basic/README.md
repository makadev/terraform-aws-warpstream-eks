# Basic WarpStream EKS

Configuration in this directory deploys a basic WarpStream cluster within EKS.

This basic deployment deploys a single WarpStream deployment for the whole region.

Pods automatically get distributed across all zones in the EKS cluster.

terraform.tfvars example:
```
aws_region="eu-central-1"
kubernetes_version="1.34"
warpstream_virtual_cluster_id="vci_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
warpstream_agent_key="aks_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```


# Startup

```sh
terraform init
terraform plan
terraform apply
```
