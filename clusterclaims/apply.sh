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

#----DEFAULTS----#
# Generate a 5-digit random cluster identifier for resource tagging purposes
RANDOM_IDENTIFIER=$(head /dev/urandom | LC_CTYPE=C tr -dc "[:lower:][:digit:]" | head -c 5 ; echo '')
SHORTNAME=$(echo $USER | head -c 8)
CLUSTERCLAIM_AUTO_IMPORT=${CLUSTERCLAIM_AUTO_IMPORT:-"false"}

#----VALIDATE PREREQ----#
# User needs to be logged into the cluster
printf "${BLUE}* Testing connection${CLEAR}\n"
if (! oc status &>/dev/null); then
    errorf "${RED}ERROR: Make sure you are logged into an OpenShift Container Platform before running this script${CLEAR}\n"
    exit 2
fi
HOST_URL=$(oc status | grep -o "https.*api.*")
# Shorten to the basedomain and tell the user which cluster we're targeting
HOST_URL=${HOST_URL/apps./}

# If HOST_URL is empty, set to something generic
if [[ -z "${HOST_URL}" ]]; then
    if [[ -n "${KUBERNETES_SERVICE_HOST}" ]]; then
        HOST_URL="<local-cluster>"
    else
        HOST_URL="<unspecifed-cluster>"
    fi
fi

printf "${BLUE}* Using cluster: ${HOST_URL}${CLEAR}\n"
VER=`oc version | grep "Server Version:"`
printf "${BLUE}* ${VER}${CLEAR}\n"


#-----CHECK FOR DRY RUN FLAG-----#
if [[ "$1" == "--dry-run" ]]; then
    CLUSTERCLAIM_DRY_RUN="true"
fi


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
    if [ "${#project_names[*]}" -eq 0 ] ; then
        errorf "${RED}There are no projects to choose from. Exiting.\n${CLEAR}"
        exit 3
    fi
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
printf "${GREEN}* Using ${CLUSTERPOOL_TARGET_NAMESPACE}\n${CLEAR}"

#----SELECT A CLUSTERPOOL TO CLAIM FROM----#
while [[ "$CLUSTERPOOL_NAME" == "" ]]; do
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
    new=$i
    printf "($i)\tCreate a new ClusterPool\n"
    printf "${BLUE}- note: to skip this step in the future, export CLUSTERPOOL_NAME${CLEAR}\n"
    printf "${YELLOW}Enter the number corresponding to ClusterPool you want to claim a cluster from:${CLEAR} "
    read selection
    if [ "$selection" -lt "$new" ]; then
        CLUSTERPOOL_NAME=${clusterpool_names[$(($selection-1))]}
    elif [ "$selection" -eq "$new" ]; then
        printf "${GREEN}* Creating a new ClusterPool using Lifeguard\n"
        cd ../clusterpools
        ./apply.sh
        cd ../clusterclaims
        printf "${GREEN}* Returning to choose a ClusterPool for your ClusterClaim\n${CLEAR}"
    else
        errorf "${RED}Invalid Choice. Exiting.\n${CLEAR}"
        exit 3
    fi
done
oc get clusterpool.hive ${CLUSTERPOOL_NAME} -n ${CLUSTERPOOL_TARGET_NAMESPACE} --no-headers &> /dev/null
if [[ $? -ne 0 ]]; then
    errorf "${RED}Couldn't find a ClusterPool named ${CLUSTERPOOL_NAME} on ${HOST_URL} in the ${CLUSTERPOOL_TARGET_NAMESPACE} namespace, validate your choice with 'oc get clusterpool.hive -n ${CLUSTERPOOL_TARGET_NAMESPACE}' and try again.${CLEAR}\n"
    exit 3
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


#-----OPTIONALLY SET A LIFETIME-----#
if [[ "$CLUSTERCLAIM_LIFETIME" == "" ]]; then
    printf "${YELLOW}Do you want to set a lifetime for this claim?  The claim will expire (automatically delete) after the lifetime passes. (Y/N) ${CLEAR}"
    read selection
    if [[ "$selection" == "Y" || "$selection" == "y" ]]; then
        printf "${BLUE}- note: to skip this step in the future, export CLUSTERCLAIM_LIFETIME=<number-of-hours>h${CLEAR}\n"
        printf "${YELLOW}How long would you like your claim to live in hours (enter a number)? ${CLEAR} "
        read selection
        if [ "$selection" != "" ]; then
            CLUSTERCLAIM_LIFETIME="${selection}h"
        else
            errorf "${RED}Empty lifetime entered. Exiting.\n${CLEAR}"
            exit 3
        fi
        printf "${GREEN}* Using Lifetime: $CLUSTERCLAIM_LIFETIME${CLEAR}\n"
    fi
fi


#-----GENERATE THE INITIAL YAML-----#
if [[ ! -d ./$CLUSTERCLAIM_NAME ]]; then
    mkdir ./$CLUSTERCLAIM_NAME
fi
TEMPLATE_FILE=./templates/clusterclaim.lifetime.yaml.template
if [[ "$CLUSTERCLAIM_LIFETIME" == "" || "$CLUSTERCLAIM_LIFETIME" == "false" ]]; then
    TEMPLATE_FILE=./templates/clusterclaim.nolifetime.yaml.template
fi
${SED} -e "s/__CLUSTERCLAIM_NAME__/$CLUSTERCLAIM_NAME/g" \
        -e "s/__CLUSTERCLAIM_AUTO_IMPORT__/$CLUSTERCLAIM_AUTO_IMPORT/g" \
        -e "s/__CLUSTERPOOL_TARGET_NAMESPACE__/$CLUSTERPOOL_TARGET_NAMESPACE/g" \
        -e "s/__CLUSTERCLAIM_LIFETIME__/$CLUSTERCLAIM_LIFETIME/g" \
        -e "s/__CLUSTERPOOL_NAME__/$CLUSTERPOOL_NAME/g" $TEMPLATE_FILE > ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml


#-----DETECT IF THE USER IS USING A SERVICE ACCOUNT - IF SO SET SUBJECT-----#
if [[ $(oc whoami | awk -F ":" '{print $2}') == "serviceaccount" ]]; then
    printf "${GREEN}* ServiceAccount use Detected, automatically adding ServiceAccount as a Subject${CLEAR}\n"
    CLUSTERCLAIM_SERVICE_ACCOUNT="$(oc whoami | awk -F ":" '{print $4}')"
    echo "" >> ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml
    ${SED} -e "s/__RBAC_SERVICEACCOUNT_NAME__/$CLUSTERCLAIM_SERVICE_ACCOUNT/g" \
        -e "s/__CLUSTERCLAIM_NAMESPACE__/$CLUSTERPOOL_TARGET_NAMESPACE/g" \
        ./templates/clusterclaim.subject.serviceaccount.yaml.template >> ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml
fi


#-----OPTIONALLY SELECT AN RBAC GROUP-----#
if [[ "$CLUSTERCLAIM_GROUP_NAME" == "" ]]; then
    printf  "${BLUE}- note: if you choose 'Y', you must have read permissions on group.user.openshift.io.${CLEAR}\n"
    printf  "${BLUE}- note: unless you are cluster-admin with clusterwide access to resouces, specifying your group is necessary to access the credentials for the claimed cluster.${CLEAR}\n"
    printf "${YELLOW}Do you want to associate this ClusterClaim with an RBAC Group? (Y/N) ${CLEAR}"
    read selection
    if [[ "$selection" == "Y" || "$selection" == "y" ]]; then
        # Prompt the user to choose an RBAC GROUP
        groups=$(oc get group -o=custom-columns=NAME:.metadata.name 2> /dev/null)
        if [[ "$?" != "0" ]]; then
            printf "${BLUE}- It looks like you don't have access to any RBAC groups (our query errored).${CLEAR}\n"
            printf "${YELLOW}Enter the name of your RBAC group: ${CLEAR}"
            read CLUSTERCLAIM_GROUP_NAME
            if [ "$CLUSTERCLAIM_GROUP_NAME" == "" ]; then
                errorf "${RED}No ClusterClaim group name entered (found empty string), exiting.${CLEAR}\n"
                exit 1
            fi
        else
            group_names=()
            i=0
            IFS=$'\n'
            for line in $groups; do
                if [ $i -eq 0 ]; then
                    printf "   \t$line\n"
                else
                    printf "($i)\t$line\n"
                    unset IFS
                    line_list=($line)
                    group_names+=(${line_list[0]})
                    IFS=$'\n'
                fi
                i=$((i+1))
            done;
            unset IFS
            printf "${BLUE}- note: to skip this step in the future, export CLUSTERCLAIM_GROUP_NAME${CLEAR}\n"
            printf "${YELLOW}Enter the number corresponding to your desired group from the list above:${CLEAR} "
            read selection
            if [ "$selection" -lt "$i" ]; then
                CLUSTERCLAIM_GROUP_NAME=${group_names[$(($selection-1))]}
            else
                errorf "${RED}Invalid Choice. Exiting.\n${CLEAR}"
                exit 3
            fi
        fi
        printf "${GREEN}* Using: $CLUSTERCLAIM_GROUP_NAME${CLEAR}\n"
        echo "" >> ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml
        if [[ "$CLUSTERCLAIM_SERVICE_ACCOUNT" == "" ]]; then
            echo "  subjects:" >> ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml
        fi
        ${SED} -e "s/__RBAC_GROUP_NAME__/$CLUSTERCLAIM_GROUP_NAME/g" ./templates/clusterclaim.subject.yaml.template >> ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml
    fi
else
    printf "${GREEN}* Using: $CLUSTERCLAIM_GROUP_NAME${CLEAR}\n"
    echo "" >> ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml
    if [[ "$CLUSTERCLAIM_SERVICE_ACCOUNT" == "" ]]; then
        echo "  subjects:" >> ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml
    fi
    ${SED} -e "s/__RBAC_GROUP_NAME__/$CLUSTERCLAIM_GROUP_NAME/g" ./templates/clusterclaim.subject.yaml.template >> ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml
fi


#-----END CLUSTERCLAIM PROCESS EARLY IF THIS IS A DRY RUN-----#
if [[ "$CLUSTERCLAIM_DRY_RUN" == "true" ]]; then
    printf "${GREEN}'--dry-run' set, skipping claim creation.  You can find your clusterclaim yaml in $(pwd)/${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml or as printed below.${CLEAR}\n"
    cat ./${CLUSTERCLAIM_NAME}/${CLUSTERCLAIM_NAME}.clusterclaim.yaml
    echo ""
    exit 0
fi


#-----CHECK FOR AVAILABLE CLUSTERS-----#
avail_clusters=$(oc get clusterpool.hive ${CLUSTERPOOL_NAME} -n ${CLUSTERPOOL_TARGET_NAMESPACE} -o json | jq -r '.status.ready')
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
    errorf "${RED}Couldn't apply ClusterClaim ${CLUSTERCLAIM_NAME} in ${CLUSTERPOOL_TARGET_NAMESPACE} on ${HOST_URL}, see the above error message for more details.${CLEAR}\n"
    exit 3
fi
printf "* ${GREEN}ClusterClaim ${CLUSTERCLAIM_NAME} on ${CLUSTERPOOL_NAME} successfully created, polling ${POLL_DURATION} seconds for claim to be fulfilled and cluster to become ready.\n${CLEAR}"


#-----EXIT IF THE USER REQUESTED TO SKIP WAIT-----#
if [[ "$SKIP_WAIT_AND_CREDENTIALS" == "true" || "$SKIP_WAIT_AND_CREDENTIALS" == "True" ]]; then
    printf "${BLUE}Skipping status polling and credential extraction.  To extract cluster credentials, run './get_credentials.sh' once the cluster is ready.${CLEAR}\n"
    printf "${GREEN}ClusterClaim ${CLUSTERCLAIM_NAME} created.${CLEAR}\n"
    exit 0
fi


#-----POLLING FOR CLAIM FULFILLMENT AND CLUSTER UNHIBERNATE-----#
# TODO: Eliminate the code duplication before this while loop by using a better looping construct
#       Alas nothing is coming to mind at the moment.
# Initialize loop variables
CC_JSON=$CLUSTERCLAIM_NAME/.ClusterClaim.json
CC_ERROR=${CC_JSON}.error
CD_JSON=$CLUSTERCLAIM_NAME/.ClusterDeployment.json
CD_ERROR=${CD_JSON}.error
oc get clusterclaim.hive ${CLUSTERCLAIM_NAME} -n ${CLUSTERPOOL_TARGET_NAMESPACE} -o json > $CC_JSON
CC_NS=`jq -r '.spec.namespace' $CC_JSON`
if [[ "$CC_NS" != "null" ]]; then
    oc get clusterdeployment $CC_NS -n $CC_NS -o json > $CD_JSON 2> $CD_ERROR
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
err_count=0
# Poll for claim to be fulfilled and ready
while [[ ("$CC_PEND_CONDITION" == "True" || "$CD_HIB_CONDITION" != "False" || "$CD_UNR_CONDITION" != "False") && "$poll_acc" -lt $POLL_DURATION ]]; do
    oc get clusterclaim.hive ${CLUSTERCLAIM_NAME} -n ${CLUSTERPOOL_TARGET_NAMESPACE} -o json > $CC_JSON 2> ${CC_ERROR}
    if (( $poll_acc > 0 && $? > 0 )); then
        printf "${BLUE}  Error getting ClusterClaim: $(cat ${CC_ERROR})\n"
        err_count=$((err_count+1))
    fi
    CC_NS=`jq -r '.spec.namespace' $CC_JSON`
    if [[ "$CC_NS" != "null" ]]; then
        oc get clusterdeployment $CC_NS -n $CC_NS -o json > $CD_JSON 2> ${CD_ERROR}
        if (( $poll_acc > 0 && $? > 0 )); then
            printf "${BLUE}  Error getting ClusterDeployment: $(cat ${CD_ERROR})\n"
            err_count=$((err_count+1))
        fi
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
    if (( $err_count > 4 )); then
        printf "${RED}Encountered repeated errors while fetching ClusterClaim or ClusterDeployment.${CLEAR}\n"
        exit 1
    fi
    printf "${BLUE}* Waited ($poll_acc/$POLL_DURATION) seconds for claim to be fulfilled and cluster to become ready. \
Status: [Pending: $CC_PEND_CONDITION:$CC_PEND_REASON] [Hibernating: $CD_HIB_CONDITION:$CD_HIB_REASON] [Unreachable: $CD_UNR_CONDITION:$CD_UNR_REASON]${CLEAR}\n"
    sleep 30
    poll_acc=$((poll_acc+30))
done
if [[ "$poll_acc" -ge $POLL_DURATION ]]; then
    if [[ "$CC_PEND_CONDITION" == "True" ]]; then
        errorf "${RED}ClusterClaim is still pending.  This likely indicates that the pool didn't have available clusters in time or the ClusterClaim was invalid.${CLEAR}\n"
        errorf "${BLUE}Final Status: [Pending: $CC_PEND_CONDITION:$CC_PEND_REASON] [Hibernating: $CD_HIB_CONDITION:$CD_HIB_REASON] [Unreachable: $CD_UNR_CONDITION:$CD_UNR_REASON]${CLEAR}\n"
        exit 3
    else
        errorf "${RED}Cluster failed to come online.  This issue can likely be resolved by deleting this Claim and creating a new one for a fresh cluster.${CLEAR}\n"
        errorf "${BLUE}Final Status: [Pending: $CC_PEND_CONDITION:$CC_PEND_REASON] [Hibernating: $CD_HIB_CONDITION:$CD_HIB_REASON] [Unreachable: $CD_UNR_CONDITION:$CD_UNR_REASON]${CLEAR}\n"
        exit 3
    fi
fi
printf "${GREEN}* Cluster ${CC_NS} successfully claimed by ${CLUSTERCLAIM_NAME}.\n"


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
