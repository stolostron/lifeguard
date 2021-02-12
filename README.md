# Lifeguard, keeping you safe in the _ClusterPools_

## Welcome!

Welcome to the Open Cluster Management _Lifeguard_ project.  _Lifeguard_ provides a series of helpful utility scripts to automate the creation, use, and management of ClusterPool, ClusterDeployment (WIP), ClusterImageSet, and ClusterClaim provided by the Open Cluster Management/Red Hat Advanced Cluster Management/Hive Projects.  Rest assured, these utility scripts don't do anything too extraordinary - ClusterPools, ClusterDeployments, ClusterClaims, and ClusterImagesets are just created and managed via Kubernetes Resources.  That means that these utility scipts just template and `oc apply` various yaml files "under the hood".  Below, we'll overview all of the "submodules" for this project - the helper scripts this project provides - and how to use them!  

*This project is still a work in progress, so there may still be gaps in logic, especially around "retry" on failed operations/user selections, we're working on patching these as we're able, and we're open to contribution!*

## Global Configuration

If you don't want colorized output or are using automation/a shell that can't show bash colorization, `export COLOR=False` for non-colorized output.  

## Installing as an `oc` Extension

You can easily install a basic version of `lifeguard` as an oc extension by running `make install-oc-extension`.  If you wish to uninstall these `oc` extensions at a later date - simply run `make uninstall-oc-extension`.  

## Prereqs

### Advanced Cluster Management/Hive Installation

If you want to use ClusterPools (the primary focus of this repo), you'll first need a Kubernetes cluster running [Hive](https://github.com/openshift/hive) v1.0.13+ or [Red Hat Advanced Cluster Managment for Kubernetes (RHACM)](https://www.redhat.com/en/technologies/management/advanced-cluster-management) 2.1.0+ (which includes a productized version of hive).  Some of the features exposed in this utility are only present in Hive v1.0.16+ and RHACM 2.2.0+, but older versions won't break this utility, just some features may not work!  Both Hive and RHACM can be installed via OperatorHub on OpenShift but you can also build and install Hive from source and the RHACM team is iterating on an installable open source project as well under the [open-cluster-management organization on GitHub](https://github.com/open-cluster-management).  

### Optional: Configuring RBAC

Once you have a cluster, we recommend that you configure RBAC groups and/or Service Accounts to federate access to your ClusterPools and ClusterDeployments.  These Kubernetes resources represent OpenShift clusters and the lifecycle of these Kubernetes resources determines the state of those OpenShift clusters, so it is important to restrict access to these resources especially when used in automation. 

We have some documentation and resources to help you make the best choices around RBAC for ClusterPools derived from our own experience using ClusterPools on RHACM to serve multitenant users (internal dev squads, not true multitenancy) and at scale within CI scenarios.  Our resources can be found in the `docs` directory of this repo, individual documents linked below:
* [Creating RBAC Groups and Setting up the Group Sync Operator](docs/creating_rbac_groups_and_groupsync.md)
* [Creating and Using Service Accounts for CI](docs/creating_and_using_service_accounts_for_CI.md)

## Creating and Consuming ClusterPools

### ClusterPools

The [ClusterPool submodule of this project](/clusterpools) provides an "easy way" to create your first ClusterPool on a target cluster.  

#### Creating a ClusterPool

To create your first ClusterPool:
1. `oc login` to the OCM/ACM/Hive cluster where you wish to host ClusterPools
2. `cd clusterpools` and run `apply.sh` (named for the `oc` command it will leverage throughout)
3. Follow the prompts, the script will guide you through all of the configuration, secret creation, and clusterpool creation.  

You may also consider defining a series of environment variables to "fully automate" the creation of additional clusterpools once you have one clusterpool under your belt.  The prompts in `apply.sh` will note which environment variable can be defined to skip a given set, but here's a full list for convenience:
```
CLUSTERPOOL_TARGET_NAMESPACE - namespace you want to create/destroy a clusterpool in
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

#### Destroying a ClusterPool

To delete a ClusterPool:
**Note:** Deleting a ClusterPool will delete all *unclaimed* clusters in the pool, but any claimed clusters (clusters with an associated ClusterClaim) will remain until the ClusterClaim is deleted.  You can check which ClusterPool a ClusterClaim is associated with by checking the `spec.clusterPoolName` entry in the ClusterClaim object via `oc get ClusterClaim <cluster-claim-name> -n <namespace> -o json | jq '.spec.clusterPoolName'`.  
1. `oc login` to the OCM/ACM/Hive cluster where you created ClusterPools
2. `cd clusterpools` and run `delete.sh` (named for the `oc` command it will leverage)
3. Follow the prompts, the script will guide you through the location and deletion of your ClusterPool

### ClusterClaims

#### Claiming a Cluster from a ClusterPool (Creating a ClusterClaim)

To claim a cluster from a ClusterPool:
1. `oc login` to the OCM/ACM/Hive cluster where you created your clusterpools
2. `cd clusterclaims` and run `apply.sh` (named for the `oc` command it will leverage throughout)
3. Follow the prompts, the script will guide you through all of the configuration, claim creation, and credentials extraction. 

You may also consider defining a series of environment variables to "fully automate" the creation of new ClusterClaims once you have one claim under your belt.  The prompts in `apply.sh` will note which environment variable can be defined to skip a given set, but here's a full list for convenience:
```
CLUSTERPOOL_TARGET_NAMESPACE - namespace you want to create/destroy a clusterpool in
CLUSTERCLAIM_NAME - chosen name for the ClusterClaim, must be unique and not contain `.`
CLUSTERPOOL_NAME - your chosen name for the clusterpool
CLUSTERCLAIM_GROUP_NAME - RBAC group to associate with the ClusterClaim
CLUSTERCLAIM_LIFETIME - lifetime for the cluster claim before automatic deletion, formatted as `1h2m3s` omitting units as desired (set to "false" to disable)
```
**Note:** If you find that the above list does not fully automate clusterclaim creation, then we made a mistake or need to update the list!  Please let us know via a GitHub issue or contribute a patch! 

#### Configuring Your `subjects` List Correctly

We overview [how we use RBAC Groups](docs/creating_rbac_groups_and_groupsync.md) and [ServiceAccounts](docs/creating_and_using_service_accounts_for_CI.md) in their own documents, but we'll overview the `subjects` list in the ClusterClaim object briefly here, as it pertains to the use of `lifeguard`.  

The `subjects` array in the ClusterClaim defines a list of RBAC entities who should be granted access to the claimed cluster and its related resources including the ClusterDeployment, User/Pass Secrets, and kubeconfig secret.  Hive will automatically grant RBAC entities in this list access to the claimed clusters' resources.  `lifeguard` handles the population of this list by:
* Automatically detecting if the user who called `lifeguard` is a ServiceAccount type user and adding that ServiceAccount to the `subjects` array
* Prompting the user to enter an RBAC Group to add to the `subjects` array - this is usually used to add the users' own RBAC group (in our case the users' team) to the claim.  

You can also add individual users, ServiceAccounts, and all ServiceAccounts in a given namespace to a claim but these operations aren't exposed in `lifeguard` yet, but we're open to requests and contributions!  

If you see the following error, you likely have a misconfigured `subjects` array and haven't been granted permissions to read your claimed clusters' credentials:
```
Error from server (Forbidden): secrets "<clusterdeployment-name>-<identifier>-admin-password" is forbidden: User "<username>" cannot get resource "secrets" in API group "" in the namespace "<clusterdeployment-name>"
```

#### Getting Credentials for a Claimed Cluster
`apply.sh` will extract the credentials for the cluster you claimed and tell you how to access those credentials but, if you have a pre-existing claim, we have a utility script to handle _just_ credential extraction.  

To extract the creentials from a pre-existing claim:
1. `oc login` to the OCM/ACM/Hive cluster where your clusterclaim resides
2. `cd clusterclaims` and run `get_credentials.sh` (named for the `oc` command it will leverage throughout, `get`)
3. Follow the prompts, the script will guide you through the credentials extraction

#### Reconciling Credential directories for Claimed Clusters
After creating multiple claims, you'll find that the directories for each are growing in number and no longer relevant. Additionally, there may have been claims created by your team that you want to access. To clean up and reconcile local claims with remote claims on the cluster, you can run `reconcile_claims.sh`.

Reconciling claims will:
1. Optionally clean out the `clusterclaims/backup/` directory
1. Move claim folders not on the remote cluster to a `clusterclaims/backup/` directory (if there are duplicate names, they will be overwritten)
2. Re-fetch all claims found remotely using `get-credentials.sh`

Set `export RECONCILE_SILENT="true"` to bypass cleaning up the backup directory and automatically force all moves (remove and replace any duplicate backups).

#### Destroying a ClusterClaim and the Claimed Cluster

To delete a ClusterClaim:
**Note:** Deleting a ClusterClaim immediately deletes the cluster that was allocated to the claim.  You can view the claimed cluster via `oc get clusterclaim <cluster-claim-name> -n <namespace> -o json | jq -r '.spec.namespace'`.  
1. `oc login` to the OCM/ACM/Hive cluster where your claim resides
2. `cd clusterclaims` and run `delete.sh` (named for the `oc` command it will leverage)
3. Follow the prompts, the script will guide you through the location and deletion of your clusterclaim
