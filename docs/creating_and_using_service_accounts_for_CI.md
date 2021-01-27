# Creating and Using Service Accounts for ClusterPools in CI/Automation

One of the primary use-cases of Clusterpools is to provide environments rapidly on-demand for CI with pre-configured security constraints, ICSPs, sizing, etc.  Clusterpools outsource the difficult, time consuming, expensive, and error-prone provisioning problem to ACM/Hive and provide an easy interface to acquire Clusters.  We use ClusterPools to drive our CI at scale (up to 72 clusters consumed by our integration tests per day).  

But - how do you interface with the cluster hosting your ClusterPools if you use token-based identity providers like GitHub?  We recommend that you use ServiceAccounts with some custom ClusterRoles and ClusterRoleBindings.  Service accounts provide token-based authentication for CI systems to use to access ClusterPools. 

## Note on ServiceAccount "Groups"

If you would like to give all service accounts in a given namespace access to clusterpools/clusterpool resources, you can optionally replace the ServiceAccount `subjects` list entries found in the following sections with a 'group' as follows:
```
subjects:
  - kind: Group
    apiGroup: rbac.authorization.k8s.io
    name: 'system:serviceaccounts:__SERVICE_ACCOUNT_NAMESPACE__'
```

## Creating a Service Account and Configuring Roles

The below yaml is a one-stop-shop for creating the necessary ClusterRoles, ServiceAccount, and ClusterRoleBindings for a clusterpool (after filling in the template items).  The following will create:

**Custom ClusterRole**
    - grants access to create/delete ClusterClaims (in order to claim clusters from our pools)

**ClusterRoleBindings**
    - `clusterpool-user` for access to create/delete clusterpools and claims
    - `view` to view the project that holds our clusterpools
    - `hive-cluster-pool-user` to [propogate permissions from pools in the namespace to the ClusterProvision/Deployment namespaces for provision failure debugging](https://github.com/openshift/hive/blob/master/docs/clusterpools.md#managing-admins-for-cluster-pools) (_technically optional_)

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
    verbs:
      - get
      - watch
      - list
      - create
      - delete
  - apiGroups:
      - 'hive.openshift.io'
    resources:
      - clusterpools
    verbs:
      - get
      - watch
      - list
---
kind: ServiceAccount
apiVersion: v1
metadata:
  name: __SERVICE_ACCOUNT_NAME__
  namespace: __SERVICE_ACCOUNT_NAMESPACE__
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: __SERVICE_ACCOUNT_NAME__-clusterpool-user
  namespace: __SERVICE_ACCOUNT_NAMESPACE__
subjects:
  - kind: ServiceAccount
    namespace: __SERVICE_ACCOUNT_NAMESPACE__
    name: __SERVICE_ACCOUNT_NAME__
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: clusterpool-user
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: __SERVICE_ACCOUNT_NAME__-view
  namespace: __SERVICE_ACCOUNT_NAMESPACE__
subjects:
  - kind: ServiceAccount
    namespace: __SERVICE_ACCOUNT_NAMESPACE__
    name: __SERVICE_ACCOUNT_NAME__
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: __SERVICE_ACCOUNT_NAME__-cluster-pool-admin
  namespace: __SERVICE_ACCOUNT_NAMESPACE__
subjects:
  - kind: ServiceAccount
    namespace: __SERVICE_ACCOUNT_NAMESPACE__
    name: __SERVICE_ACCOUNT_NAME__
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: hive-cluster-pool-admin
```

## Extracting the Token for Your Service Account

Once you've created a service account, you should be able to find the service account via:
```
gbuchana-mac:lifeguard gurnben$ oc get sa -n <sa-namespace> <sa-name>
NAME                  SECRETS   AGE
<sa-name>             2         5d23h
```
and extract the service accounts token via:
```
gbuchana-mac:lifeguard gurnben$ oc sa get-token -n <sa-namespace> <sa-name>
REDACTED
```

This token doesn't expire and can be used in your CI use-cases.  The token should regenerate if you delete the secret containing the token.  

## Usintg Your SA to Claim Clusters

You can log in to your cluster as your service account by using the `--token=` option:
```
oc login --token=<sa-token> api.<cluster-name>.<domain>:6443
```
and check that you're logged in as your SA user:
```
gbuchana-mac:lifeguard gurnben$ oc whoami
system:serviceaccount:<sa-namespace>:<sa-name>
```

If you're using the lifeguard project to claim clusters from your pool - it will automatically detect if you're using a user of type "serviceaccount" (internally it runs an `oc whoami`) and will automatically add the ServiceAccount to the `subjects` list.  That being said, you can manually add groups and/or ServiceAccounts to your ClusterClaims as follows:
```
  subjects:
  - kind: ServiceAccount
    name: '__RBAC_SERVICEACCOUNT_NAME__'
    namespace: '__CLUSTERCLAIM_NAMESPACE__'
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: '__RBAC_GROUP_NAME__'
```

As logn as the ServiceAccount is in the `subjects` list - ACM/Hive wil give the ServiceAccount permission to read the ClusterDeployment and credentials secrets for the cluster you've checked out.  
