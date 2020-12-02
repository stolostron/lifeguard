#!/bin/bash

# Color codes for bash output
BLUE='\e[36m'
GREEN='\e[32m'
RED='\e[31m'
YELLOW='\e[33m'
CLEAR='\e[39m'
if [[ "$COLOR" == "False" || "$COLOR" == "false" ]]; then
    BLUE='\e[39m'
    GREEN='\e[39m'
    RED='\e[39m'
    YELLOW='\e[39m'
fi

# Fix sed issues on mac by using GSED and fix base64 issues on macos by omitting the -w 0 parameter
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
SED="sed"
BASE64="base64 -w 0"
if [ "${OS}" == "darwin" ]; then
    SED="gsed"
    if [ ! -x "$(command -v ${SED})"  ]; then
       printf "${RED}ERROR: $SED required, but not found.${CLEAR}\n"
       printf "${RED}Perform \"brew install gnu-sed\" and try again.${CLEAR}\n"
       exit 1
    fi
    BASE64="base64"
fi

#----DEFAULTS----#
# Generate a 5-digit random cluster identifier for resource tagging purposes
RANDOM_IDENTIFIER=$(head /dev/urandom | LC_CTYPE=C tr -dc a-z0-9 | head -c 5 ; echo '')
SHORTNAME=$(echo $USER | head -c 8)

#----VALIDATE PREREQ----#
# User needs to be logged into the cluster
printf "${BLUE}* Testing connection${CLEAR}\n"
HOST_URL=`oc -n openshift-console get routes console -o jsonpath='{.status.ingress[0].routerCanonicalHostname}'`
if [ $? -ne 0 ]; then
    printf "${RED}ERROR: Make sure you are logged into an OpenShift Container Platform before running this script${CLEAR}\n"
    exit 2
fi
# Shorten to the basedomain and tell the user which cluster we're targetting
HOST_URL=${HOST_URL/apps./}
printf "${BLUE}* Using baseDomain: ${HOST_URL}${CLEAR}\n"
VER=`oc version | grep "Server Version:"`
printf "${BLUE}* ${VER}${CLEAR}\n"

#----SELECT A NAMESPACE----#
if [[ "$TARGET_NAMESPACE" == "" ]]; then
    # Prompt the user to enter a namespace name and validate their choice
    printf "${BLUE}- note: to skip this step in the future, export TARGET_NAMESPACE${CLEAR}\n"
    printf "${YELLOW}What namespace holds your clusterpools?  Your ClusterClaim will also be created in this namespace.${CLEAR} "
    read TARGET_NAMESPACE
fi
oc get ns ${TARGET_NAMESPACE} --no-headers &> /dev/null
if [[ $? -ne 0 ]]; then
    printf "${RED}Couldn't find a namespace named ${TARGET_NAMESPACE} on ${HOST_URL}, validate your choice with 'oc get ns' and try again.${CLEAR}\n"
    exit 3
fi
printf "${GREEN}* Using $TARGET_NAMESPACE\n${CLEAR}"

#----SELECT A CLUSTERPOOL TO CLAIM FROM----#
if [[ "$CLUSTERPOOL_NAME" == "" ]]; then
    # Prompt the user to choose a ClusterImageSet
    clusterpools=$(oc get clusterpools -n ${TARGET_NAMESPACE})
    clusterpool_names=()
    i=0
    IFS=$'\n'
    for line in $clusterpools; do
        if [ $i -eq 0 ]; then
            printf "   \t$line\n"
        else
            printf "($i)\t$line\n"
            unset IFS
            line_list=($line)
            clusterpool_names+=(${line_list[0]})
            IFS=$'\n'
        fi
        i=$((i+1))
    done;
    if [[ "$i" -lt 1 ]]; then
        printf "${RED}No ClusterPools found in the ${TARGET_NAMESPACE} namespace on ${HOST_URL}.  Please verify that ${TARGET_NAMESPACE} has ClusterPools with 'oc get clusterpool -n $TARGET_NAMESPACE' and try again.${CLEAR}\n"
        exit 3
    fi
    unset IFS
    printf "${BLUE}- note: to skip this step in the future, export CLUSTERPOOL_NAME${CLEAR}\n"
    printf "${YELLOW}Enter the number cooresponding to ClusterPool you want to claim a cluter from:${CLEAR} "
    read selection
    if [ "$selection" -lt "$i" ]; then
        CLUSTERPOOL_NAME=${clusterpool_names[$(($selection-1))]}
    else
        printf "${RED}Invalid Choice. Exiting.\n${CLEAR}"
        exit 3
    fi
else
    oc get clusterpool ${CLUSTERPOOL_NAME} --no-headers &> /dev/null
    if [[ $? -ne 0 ]]; then
        printf "${RED}Couldn't find a ClusterPool named ${CLUSTERPOOL_NAME} on ${HOST_URL} in the ${TARGET_NAMESPACE} namespace, validate your choice with 'oc get clusterpools -n ${TARGET_NAMESPACE}' and try again.${CLEAR}\n"
        exit 3
    fi
fi
printf "${GREEN}* Using: $CLUSTERPOOL_NAME${CLEAR}\n"


#-----SELECT A CLUSTERCLAIM NAME-----#
if [[ "$CLUSTERCLAIM_NAME" == "" ]]; then
    printf "${BLUE}- note: to skip this step in the future, export CLUSTERCLAIM_NAME${CLEAR}\n"
    printf "${YELLOW}What would you like to name your ClusterClaim  Press enter to use our generated name ($SHORTNAME-$RANDOM_IDENTIFIER-$CLUSTERPOOL_NAME)?${CLEAR} "
    read INPUT_CLUSTERCLAIM_NAME
    if [[ "$INPUT_CLUSTERCLAIM_NAME" == "" ]]; then
        CLUSTERCLAIM_NAME="$SHORTNAME-$RANDOM_IDENTIFIER-$CLUSTERPOOL_NAME"
    else
        CLUSTERCLAIM_NAME="$INPUT_CLUSTERCLAIM_NAME"
    fi
fi
printf "${GREEN}* Using: $CLUSTERCLAIM_NAME${CLEAR}\n"


#-----GENERATE THE INITIAL YAML-----#
if [[ ! -d ./$CLUSTERCLAIM_NAME ]]; then
    mkdir ./$CLUSTERCLAIM_NAME
fi
${SED} -e "s/__CLUSTERCLAIM_NAME__/$CLUSTERCLAIM_NAME/g" \
        -e "s/__TARGET_NAMESPACE__/$TARGET_NAMESPACE/g" \
        -e "s/__CLUSTERPOOL_NAME__/$CLUSTERPOOL_NAME/g" ./templates/clusterclaim.yaml.template > ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml


#-----OPTIONALLY SELECT AN RBAC GROUP-----#
printf "${YELLOW}Do you want to associate this ClusterClaim with an RBAC Group? (Y/N) ${CLEAR}"
read selection
if [[ "$selection" == "Y" || "$selection" == "y" ]]; then
    if [[ "$CLUSTERCLAIM_GROUP_NAME" == "" ]]; then
        printf "${YELLOW}What RBAC group would you like to use as the 'Subject' for this ClusterClaim (ex. a GitHub team name when group sync is in use, like CICD)?${CLEAR} "
        read CLUSTERCLAIM_GROUP_NAME
    fi
    printf "${GREEN}* Using: $CLUSTERCLAIM_GROUP_NAME${CLEAR}\n"
    echo "" >> ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml
    ${SED} -e "s/__RBAC_GROUP_NAME__/$CLUSTERCLAIM_GROUP_NAME/g" ./templates/clusterclaim.subject.yaml.template >> ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml
fi


#-----CHECK FOR AVAILABLE CLUSTERS-----#
avail_clusters=$(oc get clusterpool ${CLUSTERPOOL_NAME} -n ${TARGET_NAMESPACE} -o json | jq -r '.status.ready')
if [[ "$avail_clusters" -eq 0 ]]; then
    printf "${BLUE}* No Clusters are available in ${CLUSTERPOOL_NAME}, polling for 60 minutes after claim creation for claim to be fulfilled and awake to allow for cluster provision to occur.${CLEAR}\n"
    POLL_DURATION=3600
else
    printf "${BLUE}* $avail_clusters cluster(s) available in ${CLUSTERPOOL_NAME}, polling for 15 minutes after claim creation for claim to be fulfilled and cluster to unhibernate.${CLEAR}\n"
    POLL_DURATION=900
fi


#-----APPLYING THE CLUSTERCLAIM YAML-----#
printf "${BLUE}* Applying the following ClusterClaim yaml:${CLEAR}\n"
cat ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml
printf "\n"
oc apply -f ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml
if [[ $? -ne 0 ]]; then
    printf "${RED}Couldn't apply ClusterClaim ${CLUSTERCLAIM_NAME} in ${TARGET_NAMESPACE} on ${HOST_URL}, see the above error message for more details.${CLEAR}\n"
    exit 3
fi
printf "* ${GREEN}ClusterClaim ${CLUSTERCLAIM_NAME} on ${CLUSTERPOOL_NAME} successfully created, polling ${POLL_DURATION} seconds for claim to be fulfilled and cluster to become ready.\n${CLEAR}"


#-----POLLING FOR CLAIM FULFILLMENT AND CLUSTER UNHIBERNATE-----#
# TODO: Eliminate the code duplication before this while loop by using a better looping construct
#       Alas nothing is coming to mind at the moment.  
# Initialize loop variables
CC_JSON=$CLUSTERCLAIM_NAME/.ClusterClaim.json
CD_JSON=$CLUSTERCLAIM_NAME/.ClusterDeployment.json
oc get clusterclaim ${CLUSTERCLAIM_NAME} -n ${TARGET_NAMESPACE} -o json > $CC_JSON
CC_NS=`jq -r '.spec.namespace' $CC_JSON`
if [[ "$CC_NS" != "null" ]]; then
    oc get clusterdeployment $CC_NS -n $CC_NS -o json > $CD_JSON
else
    echo "" > $CD_JSON
fi
CC_PEND_CONDITION=`jq -r '.status.conditions[]? | select(.type=="Pending").status' $CC_JSON`
CC_PEND_CONDITION=`jq -r '.status.conditions[]? | select(.type=="Pending").status' $CC_JSON`
CC_PEND_REASON=`jq -r '.status.conditions[]? | select(.type=="Pending").reason' $CC_JSON`
if [[ "$CD_JSON" != "" ]]; then
    CD_HIB_CONDITION=`jq -r '.status.conditions[]? | select(.type=="Hibernating") | .status' $CD_JSON`
    CD_UNR_CONDITION=`jq -r '.status.conditions[]? | select(.type=="Unreachable") | .status' $CD_JSON`
else
    CD_HIB_CONDITION=""
    CD_UNR_CONDITION=""
fi
poll_acc=0
# Poll for claim to be fulfilled and ready
while [[ ("$CC_PEND_CONDITION" != "False" || "$CD_HIB_CONDITION" != "False" || "$CD_UNR_CONDITION" != "False") && "$poll_acc" -lt $POLL_DURATION ]]; do
    oc get clusterclaim ${CLUSTERCLAIM_NAME} -n ${TARGET_NAMESPACE} -o json > $CC_JSON
    CC_NS=`jq -r '.spec.namespace' $CC_JSON`
    if [[ "$CC_NS" != "null" ]]; then
        oc get clusterdeployment $CC_NS -n $CC_NS -o json > $CD_JSON
    else
        echo "" > $CD_JSON
    fi
    CC_PEND_CONDITION=`jq -r '.status.conditions[]? | select(.type=="Pending").status' $CC_JSON`
    CC_PEND_REASON=`jq -r '.status.conditions[]? | select(.type=="Pending").reason' $CC_JSON`
    if [[ "$CD_JSON" != "" ]]; then
        CD_HIB_CONDITION=`jq -r '.status.conditions[]? | select(.type=="Hibernating") | .status' $CD_JSON`
        CD_HIB_REASON=`jq -r '.status.conditions[]? | select(.type=="Hibernating") | .reason' $CD_JSON`
        CD_UNR_CONDITION=`jq -r '.status.conditions[]? | select(.type=="Unreachable") | .status' $CD_JSON`
        CD_UNR_REASON=`jq -r '.status.conditions[]? | select(.type=="Unreachable") | .reason' $CD_JSON`
    else
        CD_HIB_CONDITION=""
        CD_HIB_REASON=""
        CD_UNR_CONDITION=""
        CD_UNR_REASON=""
    fi
    printf "${BLUE}* Waited ($poll_acc/$POLL_DURATION) seconds for claim to be fulfilled and cluster to become ready. \
Status: [Pending: $CC_PEND_CONDITION:$CC_PEND_REASON] [Hibernating: $CD_HIB_CONDITION:$CD_HIB_REASON] [Unreachable: $CD_UNR_CONDITION:$CD_UNR_REASON]${CLEAR}\n"
    sleep 30
    poll_acc=$((poll_acc+30))
done
if [[ "$poll_acc" -ge $POLL_DURATION ]]; then
    if [[ "$CC_PEND_CONDITION" != "False" ]]; then
        printf "${RED}ClusterClaim is still pending.  This likely indicates that the pool didn't have available clusters in time or the ClusterClaim was invalid.${CLEAR}\n"
        printf "${BLUE}Final Status: [Pending: $CC_PEND_CONDITION:$CC_PEND_REASON] [Hibernating: $CD_HIB_CONDITION:$CD_HIB_REASON] [Unreachable: $CD_UNR_CONDITION:$CD_UNR_REASON]${CLEAR}\n"
        exit 3
    else
        printf "${RED}Cluster failed to come online.  This issue can likely be resolved by deleting this Claim and creating a new one for a fresh cluster.${CLEAR}\n"
        printf "${BLUE}Final Status: [Pending: $CC_PEND_CONDITION:$CC_PEND_REASON] [Hibernating: $CD_HIB_CONDITION:$CD_HIB_REASON] [Unreachable: $CD_UNR_CONDITION:$CD_UNR_REASON]${CLEAR}\n"
        exit 3
    fi
fi
printf "${GREEN}* Cluster ${CC_NS} successfully claimed by ${CLUSTERCLAIM_NAME}.\n"


#-----EXTRACTING CLUSTER CREDENTIALS-----#
creds_secret=`jq -r '.spec.clusterMetadata.adminPasswordSecretRef.name' $CD_JSON`
kubeconfig_secret=`jq -r '.spec.clusterMetadata.adminKubeconfigSecretRef.name' $CD_JSON`
username=`oc get secret -n $CC_NS $creds_secret -o json | jq -r '.data.username' | base64 -d`
password=`oc get secret -n $CC_NS $creds_secret -o json | jq -r '.data.password' | base64 -d`
basedomain=`jq -r '.spec.baseDomain' $CD_JSON`
api_url=`jq -r '.status.apiURL' $CD_JSON`
console_url=`jq -r '.status.webConsoleURL' $CD_JSON`
printf "${BLUE}\
{
  \"username\": \"$username\",
  \"password\": \"REDACTED\",
  \"basedomain\": \"$basedomain\",
  \"api_url\": \"$api_url\",
  \"console_url\": \"$console_url\"
}${CLEAR}\n"
echo "{
  \"username\": \"$username\",
  \"password\": \"$password\",
  \"basedomain\": \"$basedomain\",
  \"api_url\": \"$api_url\",
  \"console_url\": \"$console_url\"
}" > $CLUSTERCLAIM_NAME/$CLUSTERCLAIM_NAME.creds.json
echo $password > $CLUSTERCLAIM_NAME/kubeadmin-password
oc get secret -n $CC_NS $kubeconfig_secret -o json | jq -r '.data.kubeconfig' | base64 -d > $CLUSTERCLAIM_NAME/kubeconfig
echo "#!/bin/bash
oc login $api_url -u $username -p $password --insecure-skip-tls-verify=true" > $CLUSTERCLAIM_NAME/oc-login.sh

printf "${GREEN}Cluster credentials extracted for ${CC_NS}.  You can find full credentials in '$PWD/$CLUSTERCLAIM_NAME'.${CLEAR}\n"
