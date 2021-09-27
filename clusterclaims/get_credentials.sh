#!/bin/bash

# Error function for printing error messages to stderr
errorf() {
    printf >&2 "$@"
}

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
       errorf "${RED}ERROR: $SED required, but not found.${CLEAR}\n"
       errorf "${RED}Perform \"brew install gnu-sed\" and try again.${CLEAR}\n"
       exit 1
    fi
    BASE64="base64"
fi


#----VALIDATE PREREQ----#
# User needs to be logged into the cluster
printf "${BLUE}* Testing connection${CLEAR}\n"
HOST_URL=$(oc status | grep -o "https.*api.*")
if [ $? -ne 0 ]; then
    errorf "${RED}ERROR: Make sure you are logged into an OpenShift Container Platform before running this script${CLEAR}\n"
    exit 2
fi
# Shorten to the basedomain and tell the user which cluster we're targetting
HOST_URL=${HOST_URL/apps./}
printf "${BLUE}* Using cluster: ${HOST_URL}${CLEAR}\n"
VER=`oc version | grep "Server Version:"`
printf "${BLUE}* ${VER}${CLEAR}\n"


#----SELECT A NAMESPACE----#
if [[ "$CLUSTERPOOL_TARGET_NAMESPACE" == "" ]]; then
    # Prompt the user to choose a project
    projects=$(oc get project -o custom-columns=NAME:.metadata.name,STATUS:.status.phase)
    project_names=()
    i=0
    IFS=$'\n'
    for line in $projects; do
        if [ $i -eq 0 ]; then
            printf "   \t$line\n"
        else
            printf "($i)\t$line\n"
            unset IFS
            line_list=($line)
            project_names+=(${line_list[0]})
            IFS=$'\n'
        fi
        i=$((i+1))
    done;
    unset IFS
    printf "${BLUE}- note: to skip this step in the future, export CLUSTERPOOL_TARGET_NAMESPACE${CLEAR}\n"
    printf "${YELLOW}Enter the number corresponding to your desired Project/Namespace from the list above:${CLEAR} "
    read selection
    if [ "$selection" -lt "$i" ]; then
        CLUSTERPOOL_TARGET_NAMESPACE=${project_names[$(($selection-1))]}
    else
        errorf "${RED}Invalid Choice. Exiting.\n${CLEAR}"
        exit 3
    fi
fi
oc get projects ${CLUSTERPOOL_TARGET_NAMESPACE} --no-headers &> /dev/null
if [[ $? -ne 0 ]]; then
    errorf "${RED}Couldn't find a namespace named ${CLUSTERPOOL_TARGET_NAMESPACE} on ${HOST_URL}, validate your choice with 'oc get projects' and try again.${CLEAR}\n"
    exit 3
fi
printf "${GREEN}* Using $CLUSTERPOOL_TARGET_NAMESPACE\n${CLEAR}"


#----SELECT A CLUSTERCLAIM TO EXTRACT CREDENTIALS FROM----#
if [[ "$CLUSTERCLAIM_NAME" == "" ]]; then
    # Prompt the user to choose a ClusterImageSet
    clusterclaims=$(oc get clusterclaim.hive -n ${CLUSTERPOOL_TARGET_NAMESPACE})
    clusterclaim_names=()
    i=0
    IFS=$'\n'
    for line in $clusterclaims; do
        if [ $i -eq 0 ]; then
            printf "   \t$line\n"
        else
            printf "($i)\t$line\n"
            unset IFS
            line_list=($line)
            clusterclaim_names+=(${line_list[0]})
            IFS=$'\n'
        fi
        i=$((i+1))
    done;
    if [[ "$i" -lt 1 ]]; then
        errorf "${RED}No ClusterClaims found in the ${CLUSTERPOOL_TARGET_NAMESPACE} namespace on ${HOST_URL}.  Please verify that ${CLUSTERPOOL_TARGET_NAMESPACE} has ClusterClaims with 'oc get clusterclaim.hive -n $CLUSTERPOOL_TARGET_NAMESPACE' and try again.${CLEAR}\n"
        exit 3
    fi
    unset IFS
    printf "${BLUE}- note: to skip this step in the future, export CLUSTERCLAIM_NAME${CLEAR}\n"
    printf "${YELLOW}Enter the number corresponding to ClusterClaim you want to claim a cluster from:${CLEAR} "
    read selection
    if [ "$selection" -lt "$i" ]; then
        CLUSTERCLAIM_NAME=${clusterclaim_names[$(($selection-1))]}
    else
        errorf "${RED}Invalid Choice. Exiting.\n${CLEAR}"
        exit 3
    fi
else
    oc get clusterclaim.hive ${CLUSTERCLAIM_NAME} -n ${CLUSTERPOOL_TARGET_NAMESPACE} --no-headers &> /dev/null
    if [[ $? -ne 0 ]]; then
        errorf "${RED}Couldn't find a ClusterClaim named ${CLUSTERCLAIM_NAME} on ${HOST_URL} in the ${CLUSTERPOOL_TARGET_NAMESPACE} namespace, validate your choice with 'oc get clusterclaim.hive -n ${CLUSTERPOOL_TARGET_NAMESPACE}' and try again.${CLEAR}\n"
        exit 3
    fi
fi
printf "${GREEN}* Using: $CLUSTERCLAIM_NAME${CLEAR}\n"


#-----SET UP OUR WORKING DIRECTORY-----#
if [[ ! -d ./$CLUSTERCLAIM_NAME ]]; then
    mkdir ./$CLUSTERCLAIM_NAME
fi


#-----CHECKING FOR CLAIM FULFILLMENT-----#
# TODO: Eliminate the code duplication before this while loop by using a better looping construct
#       Alas nothing is coming to mind at the moment.
# Initialize loop variables
CC_JSON=$CLUSTERCLAIM_NAME/.ClusterClaim.json
CD_JSON=$CLUSTERCLAIM_NAME/.ClusterDeployment.json
oc get clusterclaim.hive ${CLUSTERCLAIM_NAME} -n ${CLUSTERPOOL_TARGET_NAMESPACE} -o json > $CC_JSON
CC_NS=`jq -r '.spec.namespace' $CC_JSON`
if [[ "$CC_NS" != "null" ]]; then
    oc get clusterdeployment $CC_NS -n $CC_NS -o json > $CD_JSON
else
    echo "" > $CD_JSON
fi
CC_PEND_CONDITION=`jq -r '.status.conditions[]? | select(.type=="Pending").status' $CC_JSON`
CC_PEND_REASON=`jq -r '.status.conditions[]? | select(.type=="Pending").reason' $CC_JSON`
if [[ "$CC_PEND_CONDITION" == "True" ]]; then
    errorf "${RED}Cluster is not ready, current state: [Pending: $CC_PEND_CONDITION:$CC_PEND_REASON]${CLEAR}\n"
    errorf "${RED}Unable to extract credentials until cluster is claimed.${CLEAR}\n"
    exit 3
fi
printf "${GREEN}* Cluster ${CC_NS} claimed by ${CLUSTERCLAIM_NAME}.${CLEAR}\n"


#-----EXTRACTING CLUSTER CREDENTIALS-----#
creds_secret=`jq -r '.spec.clusterMetadata.adminPasswordSecretRef.name' $CD_JSON`
kubeconfig_secret=`jq -r '.spec.clusterMetadata.adminKubeconfigSecretRef.name' $CD_JSON`
username=`oc get secret -n $CC_NS $creds_secret -o json | jq -r '.data.username' | base64 --decode`
password=`oc get secret -n $CC_NS $creds_secret -o json | jq -r '.data.password' | base64 --decode`
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
oc get secret -n $CC_NS $kubeconfig_secret -o json | jq -r '.data.kubeconfig' | base64 --decode > $CLUSTERCLAIM_NAME/kubeconfig
echo "#!/bin/bash
oc login $api_url -u $username -p $password --insecure-skip-tls-verify=true" > $CLUSTERCLAIM_NAME/oc-login.sh
chmod u+x $CLUSTERCLAIM_NAME/oc-login.sh

printf "${GREEN}Cluster credentials extracted for ${CC_NS}.  You can find full credentials in directory '$PWD/$CLUSTERCLAIM_NAME'.${CLEAR}\n"
