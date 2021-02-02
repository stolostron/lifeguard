# Configuring RBAC Groups and GroupSync

One of the primary use-cases of ClusterPools is to provide dev/test environments with pre-configured security constraints, ImageContentSourcePolicies, sizing, etc at scale across a development organization.  ClusterPools can provide these environments efficiently, quickly, and at scale to developers - eliminating the common issue of generating development environments and, when combined with [tools to toggle hibernation](https://www.openshift.com/blog/hibernate-for-cost-savings-for-advanced-cluster-management-provisioned-clusters-with-subscriptions), it can also represent a reduction in cost for development environments. 

To achieve this effectively in our experience, we needed to have development squads share access to a common "Clusterpool Host" Hub cluster with sufficient permissions to create/consume/delete clusterpools without interfering with one anothers' resources or leaking credentials cross-squad.  We accomplish this encapsulation by granting squads namespace-scoped access with each squad owning and operating within a single namespace.  This can be accomplished by creating and allocating a few roles, overviewed below.   

We mirror/generate these RBAC groups from our `open-cluster-management` GitHub organization using the [group-sync operator](https://github.com/redhat-cop/group-sync-operator) after configuring a GitHub OAuth Provider on the cluster, which we'll also overview below.  

## "Multitenancy" via Namespace-Scoped RBAC Roles

When it comes to our internal development squads, we will sometimes take the "easy route" and allocate each sqaud (represented as an RBAC group in OpenShift mirrored from GitHub via group-sync) a namespace and give the group `cluster-admin` within that namespace, but we don't recommend that most users give anyone `cluster-admin`, even on a namespace.  Instead, we recommend allocating `create` and `delete` access sparingly.  

We recommend that you create a namespace for each rbac group and grant the group the standard openshift view role and a custom clusterpool-focused role on that namespace using the ClusterRole and RoleBindings below:

Custom ClusterRoles - grants access to create/delete clusterpools, claims, and deployments as well as secrets (required for cloud platform creds and install-configs) and a separate role to grant access to the cluster-wide resource ClusterImageSets:
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
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: clusterpool-creator-clusterwide
rules:
  - apiGroups:
      - 'hive.openshift.io'
    resources:
      - clusterimagesets
    verbs:
      - get
      - watch
      - list
```

RoleBindings - `clusterpool-user` for access to create/delete clusterpools and claims, `view` to view clusterimagesets and secrets, `hive-cluster-pool-user` to propagate permissions from pools in the namespace to the ClusterProvision/Deployment namespaces for provision failure debugging (see Hive documentation on [Managing admins for Cluster Pools](https://github.com/openshift/hive/blob/master/docs/clusterpools.md#managing-admins-for-cluster-pools)), and `clusterpool-creator-clusterwide` to give access to the ClusterImageSet cluster-scoped resource:
```
kind: RoleBinding
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
kind: RoleBinding
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
---
kind: RoleBinding
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
  name: hive-cluster-pool-admin
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: <your-crb-name>
subjects:
  - kind: <one of: ServiceAccount,User,Group>
    name: <group-name>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: clusterpool-creator-clusterwide
```

You can re-use the ClusterRole (`clusterpool-user`) bound to different namespaces for different groups - that way if you ever need to expand permissions, you only have to change the role in one place.  

### Note on the `subjects` List in ClusterClaims

When defining a ClusterClaim against a pool using a user in an RBAC group or a Service Account, you'll need the add the RBAC Group and/or ServiceAccount as an item in the `subjects` array to gain permission for that SA or Group to read the ClusterDeployment, User/Pass, and Kubeconfig for the claimed cluster.  If the subjects array isn't formed properly, you won't have permission to read the access credentials for your claimed cluster.  

Lifeguard will automatically detect if you're using a ServiceAccount to create the claim and add it to the subjects array and prompt you to optionally set an RBAC group as a subject for a created claim.  For reference, when using a ServiceAccount and an RBAC group, the generated subjects array will look like:
```
spec:
  subjects:
  - kind: ServiceAccount
    name: '__RBAC_SERVICEACCOUNT_NAME__'
    namespace: '__CLUSTERCLAIM_NAMESPACE__'
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: '__RBAC_GROUP_NAME__'
```

## GitHub GroupSync

Internally, we've started leveraging the [group-sync operator](https://github.com/redhat-cop/group-sync-operator) to synchronize our GitHub teams from the [open-cluster-management](https://github.com/open-cluster-management) GitHub orgs to our dev/test/ci infrastructure clusters.  When coupled with a [GitHub Identity Provider](https://docs.openshift.com/dedicated/4/authentication/identity_providers/configuring-github-identity-provider.html), group-sync can allow you to maintain up-to-date RBAC groups for your teams and allow teams to easily authenticate via RBAC and tokens - more secure than fixed passwords.  The group-sync operator and GitHub Identity Provider config are pretty well documented, but we'll overview the configuration process below and explain how we use it with our namespace-scoped roles.  

### Installing GroupSync

1. Install the Group Sync Operator from OperatorHub or direct from the [group-sync operator](https://github.com/redhat-cop/group-sync-operator) GitHub.  
2. Create a group-sync object for GitHub after creating a `github-group-sync` secret as documented in https://github.com/redhat-cop/group-sync-operator#github
Our Group sync looks something like:
```
apiVersion: redhatcop.redhat.io/v1alpha1
kind: GroupSync
metadata:
  name: github-groupsync
spec:
  providers:
    - github:
        credentialsSecret:
          name: <github-token-secret-name, ex: github-group-sync>
          namespace: <namespace-where-group-sync-is-installed, ex: group-sync>
        organization: <your-org ex: open-cluster-management>
      name: github
  schedule: 0/30 * * * *
```
**Note:** we added a `spec.schedule` entry to have the GitHub groups sync with GitHub every 30 minutes.  
3. Run `oc get group` and verify that your groups synced from GitHub successfully.  
4. Set up a [GitHub Identity Provider](https://docs.openshift.com/dedicated/4/authentication/identity_providers/configuring-github-identity-provider.html) by following the linked instructions.  
5. OPTIONAL: For CI use-cases, you'll need to create ServiceAccounts and use token-based authentication - these service accounts can't be members of RBAC Groups, but they have their own grouping mechanism and can be assigned the same roles as your RBAC Groups.
6. OPTIONAL: Create a namespace for each Group that you want to use clusterpools (to isolate teams)
6. Configure the RoleBindings shown above with the target RBAC groups by setting the subjects list as follows, setting the namespace of the RoleBinding as desired:
```
  subjects:
    - kind: Group
      apiGroup: rbac.authorization.k8s.io
      name: <github-group>
```
7. Repeat or extend the list to include all groups you wish to have access.  In our case, we'll create RoleBindings for each Group mapping to each Groups' namespace.  

