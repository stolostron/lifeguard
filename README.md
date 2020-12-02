# Lifeguard, keeping you safe in the _ClusterPools_

## Welcome!

Welcome to the Open Cluster Management _Lifeguard_ project.  _Lifeguard_ provides a series of helpful utility scripts to automate the creation, use, and management of ClusterPool, ClusterDeployment (WIP), ClusterImageSet, and ClusterClaim (WIP) provided by the Open Cluster Management/Red Hat Advanced Cluster Management/Hive Projects.  Rest assured, these utility scripts don't do anything too extraordinary - ClusterPools, ClusterDeployments, ClusterClaims, and ClusterImagesets are just created and managed via Kubernetes Resources.  That means that these utility scipts just template and `oc apply` various yaml files "under the hood".  Below, we'll overview all of the "submodules" for this project - the helper scripts this project provides - and how to use them!  

*This project is still a work in progress, so there may still be gaps in logic, especially around "retry" on failed operations/user selections, we're working on patching these as we're able, and we're open to contribution!*

## Global Configuration

If you don't want colorized output or are using automation/a shell that can't show bash colorization, `export COLOR=False` for non-colorized output.  

## ClusterPools

The [ClusterPool submodule of this project](/clusterpools) provides an "easy way" to create your first ClusterPool on a target cluster.  

### Creating a ClusterPool

To create your first ClusterPool:
1. `oc login` to the OCM/ACM/Hive cluster where you wish to host ClusterPools
2. `cd clusterpools` and run `apply.sh` (named for the `oc` command it will leverage throughout)
3. Follow the prompts, the script will guide you through all of the configuration, secret creation, and clusterpool creation.  

You may also consider defining a series of environment variables to "fully automate" the creation of additional cluterpools once you have one clusterpool under your belt.  The prompts in `apply.sh` will note which environment variable can be defined to skip a given set, but here's a full list for convenience:
```
TARGET_NAMESPACE - namespace you want to create/destroy a clusterpool in
PLATFORM - cloud platform you wish to use, must be one of: AWS, AZURE, GCP
CLOUD_CREDENTIAL_SECRET - name of the secret to be used to access your cloud platform
OCP_PULL_SECRET - name of the secret containing your OCP pull secret
CLUSTERIMAGESET_NAME - name of the clusterimageset you wish to use for your clusterpool
CLUSTERPOOL_SIZE - "size" of your clusterpool/number of "ready" clusters in your pool
CLUSTERPOOL_NAME - your chosen name for the clusterpool
# AWS Specific
CLUSTERPOOL_AWS_REGION - aws region to use for your clusterpool
CLUSTERPOOL_AWS_BASE_DOMAIN - aws base domain to use for your clusterpool
# Azure Specific
CLUSTERPOOL_AZURE_REGION - azure region to use for your clusterpool
CLUSTERPOOL_AZURE_BASE_DOMAIN - azure base domain to use for your clusterpool
CLUSTERPOOL_AZURE_BASE_DOMAIN_RESOURCE_GROUP_NAME - name of the resource group containing your azure base domain dns zone
# GCP Specific
CLUSTERPOOL_GCP_REGION - gcp region to use for your clusterpool
CLUSTERPOOL_GCP_BASE_DOMAIN - gcp base domain to use for your clusterpool
```
**Note:** If you find that the above list does not fully automate clusterpool creation, then we made a mistake or need to update the list!  Please let us know via a GitHub issue or contribute a patch! 

### Destroying a ClusterPool

To delete a ClusterPool:
**Note:** Deleting a ClusterPool will delete all *unclaimed* clusters in the pool, but any claimed clusters (clusters with an associated ClusterClaim) will remain until the ClusterClaim is deleted.  You can check which ClusterPool a ClusterClaim is associated with by checking the `spec.clusterPoolName` entry in the ClusterClaim object via `oc get ClusterClaim <cluster-claim-name> -n <namespace> -o json | jq '.spec.clusterPoolName'`.  
1. `oc login` to the OCM/ACM/Hive cluster where you created ClusterPools
2. `cd clusterpools` and run `delete.sh` (named for the `oc` command it will leverage)
3. Follow the prompts, the script will guide you through the location and deletion of your ClusterPool

### Claiming a Cluster from a ClusterPool (Creating a ClusterClaim)

To claim a cluster from a ClusterPool:
1. `oc login` to the OCM/ACM/Hive cluster where you created your clusterpools
2. `cd clusterclaims` and run `apply.sh` (named for the `oc` command it will leverage throughout)
3. Follow the prompts, the script will guide you through all of the configuration, claim creation, and credentials extraction. 

You may also consider defining a series of environment variables to "fully automate" the creation of new ClusterClaims once you have one claim under your belt.  The prompts in `apply.sh` will note which environment variable can be defined to skip a given set, but here's a full list for convenience:
```
TARGET_NAMESPACE - namespace you want to create/destroy a clusterpool in
CLUSTERCLAIM_NAME - chosen name for the clusterclaim, must be unique and not contain `.`
CLUSTERPOOL_NAME - your chosen name for the clusterpool
```
**Note:** If you find that the above list does not fully automate clusterclaim creation, then we made a mistake or need to update the list!  Please let us know via a GitHub issue or contribute a patch! 

### Getting Credentials for a Claimed Cluster
`apply.sh` will extract the credentials for the cluster you claimed and tell you how to access those credentials but, if you have a pre-existing claim, we have a utility script to handle _just_ credential extraction.  

To extract the creentials from a pre-existing claim:
1. `oc login` to the OCM/ACM/Hive cluster where your clusterclaim resides
2. `cd clusterclaims` and run `get_credentials.sh` (named for the `oc` command it will leverage throughout, `get`)
3. Follow the prompts, the script will guide you through the credentials extraction

### Destroying a ClusterClaim and the Claimed Cluster

To delete a ClusterClaim:
**Note:** Deleting a ClusterClaim immediately deletes the cluster that was allocated to the claim.  You can view the claimed cluster via `oc get clusterclaim <cluster-claim-name> -n <namespace> -o json | jq -r '.spec.namespace'`.  
1. `oc login` to the OCM/ACM/Hive cluster where your claim resides
2. `cd clusterclaims` and run `delete.sh` (named for the `oc` command it will leverage)
3. Follow the prompts, the script will guide you through the location and deletion of your clusterclaim