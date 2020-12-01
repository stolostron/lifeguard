# Lifeguard, keeping you safe in the _ClusterPools_

## Welcome!

Welcome to the Open Cluster Management _Lifeguard_ project.  _Lifeguard_ provides a series of helpful utility scripts to automate the creation, use, and management of ClusterPool, ClusterDeployment (WIP), ClusterImageSet, and ClusterClaim (WIP) provided by the Open Cluster Management/Red Hat Advanced Cluster Management/Hive Projects.  Rest assured, these utility scripts don't do anything too extraordinary - ClusterPools, ClusterDeployments, ClusterClaims, and ClusterImagesets are just created and managed via Kubernetes Resources.  That means that these utility scipts just template and `oc apply` various yaml files "under the hood".  Below, we'll overview all of the "submodules" for this project - the helper scripts this project provides - and how to use them!  

*This project is still a work in progress, so there may still be gaps in logic, especially around "retry" on failed operations/user selections, we're working on patching these as we're able, and we're open to contribution!*

## ClusterPools

The [ClusterPool submodule of this project](/clusterpools) provides an "easy way" to create your first ClusterPool on a target cluster.  

### Creating a ClusterPool

To create your first ClusterPool:
1. `oc login` to the OCM/ACM/Hive cluster where you wish to host ClusterPools
2. Run `apply.sh` (named for the `oc` command it will leverage throughout)
3. Follow the prompts, the script will guide you through all of the configuration, secret creation, and clusterpool creation.  

You may also consider defining a series of environment variables to "fully automate" the creation of additional cluterpools once you have one clusterpool under your belt.  The prompts in `start.sh` will note which environment variable can be defined to skip a given set, but here's a full list for convenience:
```

```
**Note:** If you find that the above list does not fully automate clusterpool creation, then we made a mistake or need to update the list!  Please let us know via a GitHub issue or contribute a patch! 

### Destroying a ClusterPool

To delete a ClusterPool:
**Note:** Deleting a ClusterPool will delete all *unclaimed* clusters in the pool, but any claimed clusters (clusters with an associated ClusterClaim) will remain until the ClusterClaim is deleted.  You can check which ClusterPool a ClusterClaim is associated with by checking the `spec.clusterPoolName` entry in the ClusterClaim object via `oc get ClusterClaim <cluster-claim-name> -n <namespace> -o json | jq '.spec.clusterPoolName'`.  
1. `oc login` to the OCM/ACM/Hive cluster where you created ClusterPools
2. Run `delete.sh` (named for the `oc` command it will leverage)
3. Follow the prompts, the script will guide you through the location and deletion of your ClusterPool