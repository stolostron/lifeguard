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

#----SELECT A CLUSTERPOOL TO DELETE----#
if [[ "$CLUSTERPOOL_NAME" == "" ]]; then
    # Prompt the user to choose a ClusterImageSet
    clusterpools=$(oc get clusterpool.hive -n ${CLUSTERPOOL_TARGET_NAMESPACE})
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
    unset IFS
    printf "${BLUE}- note: to skip this step in the future, export CLUSTERPOOL_NAME${CLEAR}\n"
    printf "${YELLOW}Enter the number corresponding to your desired ClusterPool from the list above:${CLEAR} "
    read selection
    if [ "$selection" -lt "$i" ]; then
        CLUSTERPOOL_NAME=${clusterpool_names[$(($selection-1))]}
    else
        errorf "${RED}Invalid Choice. Exiting.\n${CLEAR}"
        exit 3
    fi
else
    oc get clusterpool.hive ${CLUSTERPOOL_NAME} --no-headers &> /dev/null
    if [[ $? -ne 0 ]]; then
        errorf "${RED}Couldn't find a ClusterPool named ${CLUSTERPOOL_NAME} on ${HOST_URL} in the ${CLUSTERPOOL_TARGET_NAMESPACE} namespace, validate your choice with 'oc get clusterpool.hive -n ${CLUSTERPOOL_TARGET_NAMESPACE}' and try again.${CLEAR}\n"
        exit 3
    fi
fi
printf "${GREEN}* Using: $CLUSTERPOOL_NAME${CLEAR}\n"

#-----INFORM THE USER WHICH CLUSTERCLAIMS WOULD BE ORPHANED (WITHIN CLUSTERPOOL_TARGET_NAMESPACE)-----#
clusterclaims=$(oc get clusterclaim -n $CLUSTERPOOL_TARGET_NAMESPACE -o json | jq --arg CLUSTERPOOLNAME "$CLUSTERPOOL_NAME" '.items[] | select(.spec.clusterPoolName==$CLUSTERPOOLNAME) | .metadata.name')
if [[ "$clusterclaims" != "" ]]; then
    printf "${YELLOW}The following ClusterClaims and their associated deployments will be orphaned if you delete $CLUSTERPOOL_NAME.${CLEAR}\n"
    i=1
    IFS=$'\n'
    for line in $clusterclaims; do
        printf "${YELLOW}($i)\t$line${CLEAR}\n"
    done;
    unset IFS
    printf "${BLUE}Note: these ClusterClaims and their related ClusterDeployments won't be cleaned up when you delete $CLUSTERPOOL_NAME and will stay live until you delete the ClusterClaim objects.${CLEAR}\n"
fi
printf "${YELLOW}Do you want to proceed and delete the ClusterPool: ${CLUSTERPOOL_NAME}? (Y/N) ${CLEAR}"
read selection
if [[ ! ("$selection" == "Y" || "$selection" == "y") ]]; then
    printf "${GREEN} Deletion cancelled, exiting.${CLEAR}\n"
    exit 0
else
    oc  delete clusterpool.hive -n $CLUSTERPOOL_TARGET_NAMESPACE $CLUSTERPOOL_NAME
    if [[ "$?" -ne 0 ]]; then
        errorf "${RED}Failed to delete ClusterPool $CLUSTERPOOL_NAME, see above error message for more detail.${CLEAR}\n"
        exit 3
    fi
fi
printf "${GREEN}ClusterPool ${CLUSTERPOOL_NAME} successfully deleted.${CLEAR}\n"
