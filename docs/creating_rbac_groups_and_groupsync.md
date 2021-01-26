# Configuring RBAC Groups and GroupSync

One of the primary use-cases of Clusterpools is to provide dev/test environments with pre-configured security constraints, ICSPs, sizing, etc at scale across a development organization.  Clusterpools can provide these environments efficiently, quickly, and at scale to developers - eliminating the common issue of generating development environments and, when combined with [tools to toggle hibernation](https://www.openshift.com/blog/hibernate-for-cost-savings-for-advanced-cluster-management-provisioned-clusters-with-subscriptions), it can also represent a reduction in cost for development environments. 

To achieve this effectiely in our experience, we needed to have development squads share access to a common "Clusterpool Host" Hub cluster with sufficient permissions to create/consume/delete clusterpools without interfering with one anothers' resources or leaking credentials cross-squad.  We accomplish this encapsulation by granting squads namespace-scoped access with each squad owning and operating within a single namespace.  This can be accomplished by creating and allocated a few roles, overviewed below.   

We mirror/generate these RBAC groups from our `open-cluster-management` GitHub organization using the [group-sync operator](https://github.com/redhat-cop/group-sync-operator) after configuring a GitHub OAuth Provider on the cluster, which we'll also overview below.  

## "Multitenancy" via Namespace-Scoped RBAC Roles

When it comes to our internal development squads, we will sometimes take the "easy route" and allocate each sqaud (represented as an RBAC group in OpenShift mirrored from GitHub via group-sync) a namespace and give the group `cluster-admin` within that namespace, but we don't recommend that most users give anyone `cluster-admin`, even on a namespace.  Instead, we recommend allocating `create` and `delete` access sparingly.  

We recommend that you create a namespace for each rbac group and grant the group the standard openshift view role and a custom clusterpool-focused role on that namespace using the ClusterRole and ClusterRoleBindings below:

Custom ClusterRole - grants access to create/delete clusterpools, claims, and deployments as well as secrets (required for cloud platform creds and install-configs):
```
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: clusterpool-user
rules:
  - apiGroups:
      - 'hive.openshift.io'
    resources:
      - clusterclaims
      - clusterdeployments
      - clusterpools
    verbs:
      - get
      - watch
      - list
      - create
      - delete
  - apiGroups:
      - ''
    resources:
      - secrets
    verbs:
      - get
      - watch
      - list
      - create
      - delete
```

ClusterRoleBindings:
```
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: <your-crb-name>
  namespace: <group-namespace>
subjects:
  - kind: <one of: ServiceAccount,User,Group>
    name: <group-name>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: clusterpool-user
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: <your-crb-name>
  namespace: <group-namespace>
subjects:
  - kind: <one of: ServiceAccount,User,Group>
    name: <group-name>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
```

You can re-use the ClusterRole (`clusterpool-user`) bound to different namespaces for different groups - that way if you ever need to expand permissions, you only have to change the role in one place.  

### Note on the `subjects` List in ClusterClaims and Debugging Failed Provisions

ClusterPools provision each cluster in their own namespace, housing the associated CluterProvision, ClusterDeployment, ClusterDeprovision, etc. objects in that namespace as well as the secrets holding teh password and kubeconfig for any successfully provisioned cluster.  Because all of this information is housed in another namespace, the ClusterRole and ClusterRoleBindings listed above won't give users access to the ClusterDeployment, associated secrets (user/pass), or the Cluster provision logs for any cluster created by their ClusterPool unless they claim a cluster from that pool and properly populate the `subjects` list of the ClusterClaim with their RBAC group or ServiceAccounts' name.  If the user provides RBAC targets in the subjects array, hive will allow the targets to view the claimed ClusterDeployment and Secrets.  However, users configured with the above roles and rolebindings will _not_ be able to see install logs for their ClusterPool clusters, so if they hit a quota or configuration issue, the admin will have to step in to provide debugging information.  The Hive and ACM teams are working on a resolution which will allow ClusterPools to propagate permissions to ClusterProvisions similar to the propagation seen with claims.  

`lifeguard` automatically prompts the user to enter an rbac group name if desired and automatically detects and adds a ServiceAccount name if `lifegaurd` was invoked by a service account.  