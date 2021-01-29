#! /bin/bash

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

#----VALIDATE PREREQ----#
# User needs to be logged into the cluster
printf "${BLUE}* Testing connection${CLEAR}\n"
HOST_URL=$(oc status | grep -o "https.*api.*")
if [ $? -ne 0 ]; then
    printf "${RED}ERROR: Make sure you are logged into an OpenShift Container Platform before running this script${CLEAR}\n"
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
        printf "${RED}Invalid Choice. Exiting.\n${CLEAR}"
        exit 3
    fi
fi
oc get projects ${CLUSTERPOOL_TARGET_NAMESPACE} --no-headers &> /dev/null
if [[ $? -ne 0 ]]; then
    printf "${RED}Couldn't find a namespace named ${CLUSTERPOOL_TARGET_NAMESPACE} on ${HOST_URL}, validate your choice with 'oc get projects' and try again.${CLEAR}\n"
    exit 3
fi
printf "${GREEN}* Using $CLUSTERPOOL_TARGET_NAMESPACE\n${CLEAR}"

REMOTE_CLAIMS=$(oc get clusterclaims -n ${CLUSTERPOOL_TARGET_NAMESPACE} --no-headers -o custom-columns="NAME:metadata.name")
LOCAL_CLAIMS=$(ls -d1 ./*/ | grep -v "templates\|backup" | sed 's/^\.\///' | sed 's/\/$//')
DIFF_CLAIMS=$(comm -1 -3 <(echo "${REMOTE_CLAIMS}") <(echo "${LOCAL_CLAIMS}"))
if [[ -n "${DIFF_CLAIMS}" ]]; then
    if (ls -d1 backup/*/ &>/dev/null); then
        printf "${YELLOW}Would you like to remove the existing claim backups in ./backup (y/n)? ${CLEAR}"
        read selection
        case "$selection" in
                y|Y )   printf "${GREEN}* Removing all directories stored in ./backup\n${CLEAR}"
                        rm -r ./backup/*/
                        ;;
        esac
    fi
    printf "${BLUE}* Moving existing claim directories not found remotely to ./backup folder:\n${CLEAR}"
    for claim_dir in ${DIFF_CLAIMS}; do
        if (! ls ./backup/ &>/dev/null); then
            mkdir backup
        fi
        MOVED="false"
        if (! mv "${claim_dir}" ./backup/ &>/dev/null); then
            printf "${YELLOW}Error moving ClusterClaim directory ${claim_dir}. Would you like to try overwriting any existing directories (y/n)? ${CLEAR}"
            read selection
            case "$selection" in
                    y|Y )   printf "${GREEN}* Attempting force move of ${claim_dir}\n${CLEAR}"
                            rm -rf ./backup/${claim_dir}/ &>/dev/null
                            MOVED=$(mv -f "${claim_dir}" ./backup/ && echo "true" || echo "false")
                            ;;
            esac
        else
            MOVED="true"
        fi
        if [[ "${MOVED}" == "true" ]]; then
            printf "* Moved: ${claim_dir}\n"
        else
            printf "* Not moved: ${claim_dir}\n"
        fi
    done
else
    printf "${BLUE}* Local ClusterClaim directories do not differ from the remote ClusterClaims\n${CLEAR}"
fi

if [[ -n "${REMOTE_CLAIMS}" ]]; then
    printf "${BLUE}* Re-initializing claim directories using remote ClusterClaims\n${CLEAR}"
    REMOTE_CLAIMS=$(oc get clusterclaims -n ${CLUSTERPOOL_TARGET_NAMESPACE} --no-headers -o custom-columns="NAME:metadata.name")
    for CLUSTERCLAIM_NAME in ${REMOTE_CLAIMS}; do
        export CLUSTERPOOL_TARGET_NAMESPACE=${CLUSTERPOOL_TARGET_NAMESPACE}
        export CLUSTERCLAIM_NAME=${CLUSTERCLAIM_NAME}
        printf "* Fetching ${CLUSTERCLAIM_NAME}..."
        ./get_credentials.sh 1>/dev/null
        printf "done\n"
    done
else
    printf "${BLUE}* No remote ClusterClaims found\n${CLEAR}"
fi