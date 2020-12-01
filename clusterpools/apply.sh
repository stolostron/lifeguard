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

generate_aws_secret() {
    if [[ "$AWS_ACCESS_KEY_ID" != "" && "$AWS_SECRET_ACCESS_KEY" != "" ]]; then
        printf "${YELLOW}Do you want to use the current values of the environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (Y/N)?${CLEAR} "
        read selection
        if [[ "$selection" == "Y" || "$selection" == "y" ]]; then
            AWS_ACCESS_KEY_ID_UNENCODED=$AWS_ACCESS_KEY_ID
            AWS_SECRET_ACCESS_KEY_UNENCODED=$AWS_SECRET_ACCESS_KEY
        else
            printf "${YELLOW}Enter your AWS Access Key:${CLEAR} "
            read AWS_ACCESS_KEY_ID_UNENCODED
            printf "${YELLOW}Enter your AWS Secret Access Key:${CLEAR} "
            read AWS_SECRET_ACCESS_KEY_UNENCODED
        fi
    else
        printf "${YELLOW}Enter your AWS Access Key:${CLEAR} "
        read AWS_ACCESS_KEY_ID_UNENCODED
        printf "${YELLOW}Enter your AWS Secret Access Key:${CLEAR} "
        read AWS_SECRET_ACCESS_KEY_UNENCODED
    fi
    printf "${BLUE}Creating a new secret in the namespace ${TARGET_NAMESPACE} named ${SHORTNAME}-aws-creds to contain your AWS Credentials for Cluster Provisions.${CLEAR}\n"
    oc create secret generic $SHORTNAME-aws-creds -n ${TARGET_NAMESPACE} --from-literal=aws_access_key_id=$AWS_ACCESS_KEY_ID_UNENCODED --from-literal=aws_secret_access_key=$AWS_SECRET_ACCESS_KEY_UNENCODED
    if [[ "$?" != "0" ]]; then
        printf "${RED}Unable to create AWS Credentials Secret. See above message for errors.  Exiting."
        exit 3
    fi
    CLOUD_CREDENTIAL_SECRET=$SHORTNAME-aws-creds
}

generate_azure_secret() {
    AZURE_SERVICE_PRINCIPLE_JSON=${AZURE_SERVICE_PRINCIPLE_JSON:-"$HOME/.azure/osServicePrincipal.json"}
    if [[ -f $AZURE_SERVICE_PRINCIPLE_JSON ]]; then
        printf "${YELLOW}Do you want to use the credentials stored in $AZURE_SERVICE_PRINCIPLE_JSON (Y/N)?${CLEAR} "
        read selection
        if [[ ! ("$selection" == "Y" || "$selection" == "y") ]]; then
            printf "${YELLOW}Enter your Azure Subscription ID:${CLEAR} "
            read AZURE_SUBSCRIPTION_ID
            printf "${YELLOW}Enter your Azure Client ID:${CLEAR} "
            read AZURE_CLIENT_ID
            printf "${YELLOW}Enter your Azure Client Secret:${CLEAR} "
            read AZURE_CLIENT_SECRET
            printf "${YELLOW}Enter your Azure Tenant ID:${CLEAR} "
            read AZURE_TENANT_ID
            printf "${BLUE}Storing Azure details in $AZURE_SERVICE_PRINCIPLE_JSON for future reuse, emulating the behavior of the openshift-install binary"
            if [[ ! -d ~/.azure ]]; then
                mkdir ~/.azure
            fi
            echo "{\"subscriptionId\":\"$AZURE_SUBSCRIPTION_ID\",\"clientId\":\"$AZURE_CLIENT_ID\",\"clientSecret\":\"$AZURE_CLIENT_SECRET\",\"tenantId\":\"$AZURE_TENANT_ID\"}" > $AZURE_SERVICE_PRINCIPLE_JSON
        fi
    else
        printf "${YELLOW}Enter your Azure Subscription ID:${CLEAR} "
        read AZURE_SUBSCRIPTION_ID
        printf "${YELLOW}Enter your Azure Client ID:${CLEAR} "
        read AZURE_CLIENT_ID
        printf "${YELLOW}Enter your Azure Client Secret:${CLEAR} "
        read AZURE_CLIENT_SECRET
        printf "${YELLOW}Enter your Azure Tenant ID:${CLEAR} "
        read AZURE_TENANT_ID
        printf "${BLUE}Storing Azure details in $AZURE_SERVICE_PRINCIPLE_JSON for future reuse, emulating the behavior of the openshift-install binary"
        if [[ ! -d ~/.azure ]]; then
            mkdir ~/.azure
        fi
        echo "{\"subscriptionId\":\"$AZURE_SUBSCRIPTION_ID\",\"clientId\":\"$AZURE_CLIENT_ID\",\"clientSecret\":\"$AZURE_CLIENT_SECRET\",\"tenantId\":\"$AZURE_TENANT_ID\"}" > $AZURE_SERVICE_PRINCIPLE_JSON
    fi
    printf "${BLUE}Creating a new secret in the namespace ${TARGET_NAMESPACE} named ${SHORTNAME}-azure-creds to contain your Azure Credentials for Cluster Provisions.${CLEAR}\n"
    oc create secret generic $SHORTNAME-azure-creds -n ${TARGET_NAMESPACE} --from-file=osServicePrincipal.json=$AZURE_SERVICE_PRINCIPLE_JSON
    if [[ "$?" != "0" ]]; then
        printf "${RED}Unable to create Azure Credentials Secret. See above message for errors.  Exiting."
        exit 3
    fi
    CLOUD_CREDENTIAL_SECRET=$SHORTNAME-azure-creds
}

generate_gcp_secret() {
    GCP_SERVICE_ACCOUNT_JSON=${GCP_SERVICE_ACCOUNT_JSON:-"$HOME/.gcp/osServiceAccount.json"}
    if [[ -f $GCP_SERVICE_ACCOUNT_JSON ]]; then
        printf "${YELLOW}Do you want to use the credentials stored in $GCP_SERVICE_ACCOUNT_JSON (Y/N)?${CLEAR} "
        read selection
        if [[ ! ("$selection" == "Y" || "$selection" == "y") ]]; then
            printf "${BLUE}- note: if you don't have a GCP Service Account JSON file, you can download it via the GCP console.${CLEAR}\n"
            printf "${YELLOW}Enter the path to the GCP Service Account JSON you would like to use:${CLEAR} "
            read GCP_SERVICE_ACCOUNT_JSON_ALT
            printf "${BLUE}Storing GCP details in $GCP_SERVICE_ACCOUNT_JSON for future reuse, emulating the behavior of the openshift-install binary"
            if [[ ! -d ~/.gcp ]]; then
                mkdir ~/.gcp
            fi
            cp $GCP_SERVICE_ACCOUNT_JSON_ALT $GCP_SERVICE_ACCOUNT_JSON
        fi
    else
        printf "${BLUE}- note: if you don't have a GCP Service Account JSON file, you can download it via the GCP console.${CLEAR}\n"
        printf "${YELLOW}Enter the path to your GCP Service Account JSON:${CLEAR} "
        read GCP_SERVICE_ACCOUNT_JSON_ALT
        printf "${BLUE}Storing GCP details in $GCP_SERVICE_ACCOUNT_JSON for future reuse, emulating the behavior of the openshift-install binary"
        if [[ ! -d ~/.gcp ]]; then
            mkdir ~/.gcp
        fi
        cp $GCP_SERVICE_ACCOUNT_JSON_ALT $GCP_SERVICE_ACCOUNT_JSON
    fi
    printf "${BLUE}Creating a new secret in the namespace ${TARGET_NAMESPACE} named ${SHORTNAME}-gcp-creds to contain your GCP Credentials for Cluster Provisions.${CLEAR}\n"
    oc create secret generic $SHORTNAME-gcp-creds -n ${TARGET_NAMESPACE} --from-file=osServicePrincipal.json=$GCP_SERVICE_ACCOUNT_JSON
    if [[ "$?" != "0" ]]; then
        printf "${RED}Unable to create GCP Credentials Secret. See above message for errors.  Exiting."
        exit 3
    fi
    CLOUD_CREDENTIAL_SECRET=$SHORTNAME-gcp-creds
}

generate_openshift_pull_secret() {
    OCP_PULL_SECRET=${OCP_PULL_SECRET:-"./pull-secret.txt"}
    if [[ -f $OCP_PULL_SECRET ]]; then
        printf "${YELLOW}Do you want to use the pull secret stored in $OCP_PULL_SECRET (Y/N)?${CLEAR} "
        read selection
        if [[ ! ("$selection" == "Y" || "$selection" == "y") ]]; then
            printf "${BLUE}- note: if you don't have an OCP Pull Secret, you can download the file from https://cloud.redhat.com/openshift/install/aws/installer-provisioned${CLEAR}\n"
            printf "${YELLOW}Enter the path to the OCP pull secret file:${CLEAR} "
            read OCP_PULL_SECRET_INPUT
            printf "${BLUE}Storing OCP Pull Secret in $OCP_PULL_SECRET for future reuse"
            cp $OCP_PULL_SECRET_INPUT $OCP_PULL_SECRET
        fi
    else
        printf "${BLUE}- note: if you don't have an OCP Pull Secret, you can download the file from https://cloud.redhat.com/openshift/install/aws/installer-provisioned${CLEAR}\n"
        printf "${YELLOW}Enter the path to the OCP pull secret file:${CLEAR} "
        read OCP_PULL_SECRET_INPUT
        printf "${BLUE}Storing OCP Pull Secret in $OCP_PULL_SECRET for future reuse"
        cp $OCP_PULL_SECRET_INPUT $OCP_PULL_SECRET
    fi
    printf "${BLUE}Creating a new secret in the namespace ${TARGET_NAMESPACE} named ${SHORTNAME}-ocp-pull-secret to contain your OCP Pull Secret for Cluster Provisions.${CLEAR}\n"
    oc create secret generic ${SHORTNAME}-ocp-pull-secret --from-file=.dockerconfigjson=$OCP_PULL_SECRET --type=kubernetes.io/dockerconfigjson --namespace ${TARGET_NAMESPACE}
    if [[ "$?" != "0" ]]; then
        printf "${RED}Unable to create OCP Pull Secret. See above message for errors.  Exiting."
        exit 3
    fi
    OCP_PULL_SECRET=${SHORTNAME}-ocp-pull-secret
}

generate_clusterimageset() {
    printf "${BLUE}ClusterImageSets can only reference OCP installer images from https://quay.io/repository/openshift-release-dev/ocp-release${CLEAR}\n"
    printf "${YELLOW}What OpenShift Version would you like to create a ClusterImageSet for (ex. 4.6.4)?${CLEAR} "
    read CLUSTERIMAGESET_OCP_VERSION
    IMAGE="https://quay.io/api/v1/repository/openshift-release-dev/ocp-release/tag/?specificTag=$CLUSTERIMAGESET_OCP_VERSION-x86_64"
    IMAGE_LIST=$(curl -X GET $IMAGE -s)
    IMAGE_MATCHES=$(echo $IMAGE_LIST | jq '.tags | length')
    if [[ "$IMAGE_MATCHES" -le 0 ]]; then
        printf "${RED}Couldn't find an image for quay.io/openshift-release-dev/ocp-release:$CLUSTERIMAGESET_OCP_VERSION-x86_64, validate the desired version and try again.  Exiting.${CLEAR}\n"
        exit 3
    else
        CLUSTERIMAGESET_RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:${CLUSTERIMAGESET_OCP_VERSION}-x86_64"
    fi
    printf "${GREEN}* Using Release Image ${CLUSTERIMAGESET_RELEASE_IMAGE} found for version ${CLUSTERIMAGESET_OCP_VERSION}${CLEAR}\n"
    CLUSTERIMAGESET_NAME="openshift-v$(echo $CLUSTERIMAGESET_OCP_VERSION | sed 's/\.//g')"
    printf "${YELLOW}What would you like to name your imageset?  Press enter to use the default name ($CLUSTERIMAGESET_NAME).${CLEAR} "
    read CLUSTERIMAGESET_NAME_INPUT
    if [[ "$CLUSTERIMAGESET_NAME_INPUT" != "" ]]; then
        CLUSTERIMAGESET_NAME=$CLUSTERIMAGESET_NAME_INPUT
    fi
    if [[ ! -d $CLUSTERIMAGESET_NAME-clusterimageset ]]; then
        mkdir $CLUSTERIMAGESET_NAME-clusterimageset
    fi
    ${SED} -e "s|__CLUSTERIMAGESET_NAME__|$CLUSTERIMAGESET_NAME|g" \
           -e "s|__CLUSTERIMAGESET_RELEASE_IMAGE__|$CLUSTERIMAGESET_RELEASE_IMAGE|g" ./templates/clusterimageset.yaml.template > ./${CLUSTERIMAGESET_NAME}-clusterimageset/${CLUSTERIMAGESET_NAME}.clusterimageset.yaml
    printf "${BLUE}* Applying the ClusterImageSet yaml:\n"
    cat ./${CLUSTERIMAGESET_NAME}-clusterimageset/${CLUSTERIMAGESET_NAME}.clusterimageset.yaml
    printf "${CLEAR}\n"
    oc apply -f ./${CLUSTERIMAGESET_NAME}-clusterimageset/${CLUSTERIMAGESET_NAME}.clusterimageset.yaml
    if [[ "$?" -ne 0 ]]; then
        printf "${RED}Failed to create ClusterImageSet $CLUSTERIMAGESET_NAME, see above error message for more detail.  This is likely a permissions issue - ClusterImageSets are a global cluster resource.${CLEAR}\n"
        exit 3
    fi
}

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

#----DEFAULTS----#
# Generate a 5-digit random cluster identifier for resource tagging purposes
RANDOM_IDENTIFIER=$(head /dev/urandom | LC_CTYPE=C tr -dc a-z0-9 | head -c 5 ; echo '')
SHORTNAME=$(echo $USER | head -c 8)

# Generate a default resource name
GENERATED_CLUSTERPOOL_NAME="$SHORTNAME-$RANDOM_IDENTIFIER"

#----SELECT A NAMESPACE----#
if [[ "$TARGET_NAMESPACE" == "" ]]; then
    # Prompt the user to enter a namespace name and validate their choice
    printf "${BLUE}- note: to skip this step in the future, export TARGET_NAMESPACE${CLEAR}\n"
    printf "${YELLOW}What namespace do you want to use for ClusterPools?${CLEAR} "
    read TARGET_NAMESPACE
fi
oc get ns ${TARGET_NAMESPACE} --no-headers &> /dev/null
if [[ $? -ne 0 ]]; then
    printf "${RED}Couldn't find a namespace named ${TARGET_NAMESPACE} on ${HOST_URL}, validate your choice with 'oc get ns' and try again.${CLEAR}\n"
    exit 3
fi
printf "${GREEN}* Using $TARGET_NAMESPACE\n${CLEAR}"


#----SELECT A cloud platform----#
platforms=("AWS" "AZURE" "GCP")
if [[ "$PLATFORM" == "" ]]; then
    # Prompt the user to choose a cloud platform to create a pool on
    i=0
    for platform in ${platforms[@]}; do
        printf "($((i+1))) $platform\n"
        i=$((i+1))
    done
    printf "${BLUE}- note: to skip this step in the future, export PLATFORM=<AWS, AZURE, GCP>${CLEAR}\n"
    printf "${YELLOW}Enter the number cooresponding to your desired Cloud Platform from the list above:${CLEAR} "
    read selection
    if [ $selection -ge $((i+1)) ]; then
        printf "${RED}Invalid Choice. Exiting.\n${CLEAR}"
    fi
    PLATFORM=${platforms[$((selection-1))]}
else
    found=0
    for platform in $platforms; do
        if [[ "$platform" == "$PLATFORM" ]]; then
            found=1
        fi
    done;
    if [ "$found" -ne 1 ]; then
        printf "${RED}Invalid value $PLATFORM for the variable PLATFORM.  Choose from: $platforms. Exiting.\n${CLEAR}"
        exit 3
    fi
fi
printf "${GREEN}* Using $PLATFORM\n${CLEAR}"


#----SELECT OR CREATE CLOUD CREDENTIALS----#
if [[ "$CLOUD_CREDENTIAL_SECRET" == "" ]]; then
    # Prompt the user to choose a Cloud Credential Secret
    secrets=$(oc get secrets -n $TARGET_NAMESPACE)
    secret_names=()
    i=0
    IFS=$'\n'
    for line in $secrets; do
        if [ $i -eq 0 ]; then
            printf "   \t$line\n"
        else
            printf "($i)\t$line\n"
            unset IFS
            line_list=($line)
            secret_names+=(${line_list[0]})
            IFS=$'\n'
        fi
        i=$((i+1))
    done;
    unset IFS
    new=$i
    printf "($i)\tCreate a new Secret.\n"
    printf "${BLUE}- note: to skip this step in the future, export CLOUD_CREDENTIAL_SECRET${CLEAR}\n"
    printf "${YELLOW}Enter the number cooresponding to your desired Secret from the list above:${CLEAR} "
    read selection
    if [ "$selection" -lt "$new" ]; then
        CLOUD_CREDENTIAL_SECRET=${secret_names[$(($selection-1))]}
    elif [ "$selection" -eq "$new" ]; then
        if [[ "$PLATFORM" == "AWS" ]]; then
            generate_aws_secret
        elif [[ "$PLATFORM" == "AZURE" ]]; then
            generate_azure_secret
        elif [[ "$PLATFORM" == "GCP" ]]; then
            generate_gcp_secret
        else
            printf "${RED}Unsupported platform ${PLATFORM} detected, secret creation wizard only supports AWS, AZURE, and GCP.  Exiting.${CLEAR}"
            exit 3
        fi
    else
        printf "${RED}Invalid Choice. Exiting.\n${CLEAR}"
        exit 3
    fi
else
    oc get secret ${CLOUD_CREDENTIAL_SECRET} --no-headers &> /dev/null
    if [[ $? -ne 0 ]]; then
        printf "${RED}Couldn't find a secret named ${CLOUD_CREDENTIAL_SECRET} in the ${TARGET_NAMESPACE} namespace on ${HOST_URL}, validate your choice with 'oc get secrets -n $TARGET_NAMESPACE' and try again.${CLEAR}\n"
        exit 3
    fi
fi
printf "${GREEN}* Using $CLOUD_CREDENTIAL_SECRET\n${CLEAR}"


#----SELECT OR CREATE OCP PULL SECRET----#
if [[ "$OCP_PULL_SECRET" == "" ]]; then
    # Prompt the user to choose an OCP Pull Secret
    secrets=$(oc get secrets -n $TARGET_NAMESPACE)
    secret_names=()
    i=0
    IFS=$'\n'
    for line in $secrets; do
        if [ $i -eq 0 ]; then
            printf "   \t$line\n"
        else
            printf "($i)\t$line\n"
            unset IFS
            line_list=($line)
            secret_names+=(${line_list[0]})
            IFS=$'\n'
        fi
        i=$((i+1))
    done;
    unset IFS
    new=$i
    printf "($i)\tCreate a new Secret.\n"
    printf "${BLUE}- note: to skip this step in the future, export OCP_PULL_SECRET${CLEAR}\n"
    printf "${YELLOW}Enter the number cooresponding to your desired Secret from the list above:${CLEAR} "
    read selection
    if [ "$selection" -lt "$new" ]; then
        OCP_PULL_SECRET=${secret_names[$(($selection-1))]}
    elif [ "$selection" -eq "$new" ]; then
        generate_openshift_pull_secret
    else
        printf "${RED}Invalid Choice. Exiting.\n${CLEAR}"
        exit 3
    fi
else
    oc get secret ${OCP_PULL_SECRET} --no-headers &> /dev/null
    if [[ $? -ne 0 ]]; then
        printf "${RED}Couldn't find a secret named ${OCP_PULL_SECRET} in the ${TARGET_NAMESPACE} namespace on ${HOST_URL}, validate your choice with 'oc get secrets -n $TARGET_NAMESPACE' and try again.${CLEAR}\n"
        exit 3
    fi
fi
printf "${GREEN}* Using $OCP_PULL_SECRET\n${CLEAR}"


#----SELECT OR CREATE CLUSTERIMAGESET----#
if [[ "$CLUSTERIMAGESET_NAME" == "" ]]; then
    # Prompt the user to choose a ClusterImageSet
    clusterimagesets=$(oc get clusterimagesets)
    clusterimageset_names=()
    i=0
    IFS=$'\n'
    for line in $clusterimagesets; do
        if [ $i -eq 0 ]; then
            printf "   \t$line\n"
        else
            printf "($i)\t$line\n"
            unset IFS
            line_list=($line)
            clusterimageset_names+=(${line_list[0]})
            IFS=$'\n'
        fi
        i=$((i+1))
    done;
    unset IFS
    new=$i
    printf "($i)\tCreate a new ClusterImageSet.\n"
    printf "${BLUE}- note: to skip this step in the future, export CLUSTERIMAGESET_NAME${CLEAR}\n"
    printf "${YELLOW}Enter the number cooresponding to your desired ClusterImageSet from the list above:${CLEAR} "
    read selection
    if [ "$selection" -lt "$new" ]; then
        CLUSTERIMAGESET_NAME=${clusterimageset_names[$(($selection-1))]}
    elif [ "$selection" -eq "$new" ]; then
        generate_clusterimageset
    else
        printf "${RED}Invalid Choice. Exiting.\n${CLEAR}"
        exit 3
    fi
else
    oc get ClusterImageSet ${CLUSTERIMAGESET_NAME} --no-headers &> /dev/null
    if [[ $? -ne 0 ]]; then
        printf "${RED}Couldn't find a ClusterImageSet named ${CLUSTERIMAGESET_NAME} on ${HOST_URL}, validate your choice with 'oc get clusterimagesets' and try again.${CLEAR}\n"
        exit 3
    fi
fi
printf "${GREEN}* Using: $CLUSTERIMAGESET_NAME${CLEAR}\n"


#----GET CLOUD PLATFORM SPECIFIC DETAILS----#
if [[ "$PLATFORM" == "AWS" ]]; then
    if [[ "$CLUSTERPOOL_AWS_REGION" == "" ]]; then
        printf "${BLUE}- note: to skip this step in the future, export CLUSTERPOOL_AWS_REGION${CLEAR}\n"
        printf "${YELLOW}Which AWS Region would you like to use to house your ClusterPool (ex. us-east-1)?${CLEAR} "
        read CLUSTERPOOL_AWS_REGION
    fi
    printf "${GREEN}* Using AWS Region ${CLUSTERPOOL_AWS_REGION}${CLEAR}\n"
    if [[ "$CLUSTERPOOL_AWS_BASE_DOMAIN" == "" ]]; then
        printf "${BLUE}- note: to skip this step in the future, export CLUSTERPOOL_AWS_BASE_DOMAIN${CLEAR}\n"
        printf "${YELLOW}What Base Domain should be used for your ClusterPool Clusters (ex. mydomain.com)?${CLEAR} "
        read CLUSTERPOOL_AWS_BASE_DOMAIN
    fi
    printf "${GREEN}* Using AWS Base Domain ${CLUSTERPOOL_AWS_BASE_DOMAIN}${CLEAR}\n"
elif [[ "$PLATFORM" == "AZURE" ]]; then
    if [[ "$CLUSTERPOOL_AZURE_REGION" == "" ]]; then
        printf "${BLUE}- note: to skip this step in the future, export CLUSTERPOOL_AZURE_REGION${CLEAR}\n"
        printf "${YELLOW}Which Azure Region would you like to use to house your ClusterPool (ex. eastus)?${CLEAR} "
        read CLUSTERPOOL_AZURE_REGION
    fi
    printf "${GREEN}* Using Azure Region ${CLUSTERPOOL_AZURE_REGION}${CLEAR}\n"
    if [[ "$CLUSTERPOOL_AZURE_BASE_DOMAIN" == "" ]]; then
        printf "${BLUE}- note: to skip this step in the future, export CLUSTERPOOL_AZURE_BASE_DOMAIN${CLEAR}\n"
        printf "${YELLOW}What Base Domain should be used for your ClusterPool Clusters (ex. mydomain.com)?${CLEAR} "
        read CLUSTERPOOL_AZURE_BASE_DOMAIN
    fi
    if [[ "$CLUSTERPOOL_AZURE_BASE_DOMAIN_RESOURCE_GROUP_NAME" == "" ]]; then
        printf "${BLUE}- note: to skip this step in the future, export CLUSTERPOOL_AZURE_BASE_DOMAIN_RESOURCE_GROUP_NAME${CLEAR}\n"
        printf "${YELLOW}What Resource Group contains your Base Domain DNS Zone (ex. mybasedomainresourcegroup)?${CLEAR} "
        read CLUSTERPOOL_AZURE_BASE_DOMAIN_RESOURCE_GROUP_NAME
    fi
    printf "${GREEN}* Using Azure Base Domain ${CLUSTERPOOL_AZURE_BASE_DOMAIN} from Resource Group ${CLUSTERPOOL_AZURE_BASE_DOMAIN_RESOURCE_GROUP_NAME}${CLEAR}\n"
elif [[ "$PLATFORM" == "GCP" ]]; then
    if [[ "$CLUSTERPOOL_GCP_REGION" == "" ]]; then
        printf "${BLUE}- note: to skip this step in the future, export CLUSTERPOOL_GCP_REGION${CLEAR}\n"
        printf "${YELLOW}Which GCP Region would you like to use to house your ClusterPool (ex. us-east1)?${CLEAR} "
        read CLUSTERPOOL_GCP_REGION
    fi
    printf "${GREEN}* Using GCP Region ${CLUSTERPOOL_GCP_REGION}${CLEAR}\n"
    if [[ "$CLUSTERPOOL_GCP_BASE_DOMAIN" == "" ]]; then
        printf "${BLUE}- note: to skip this step in the future, export CLUSTERPOOL_GCP_BASE_DOMAIN${CLEAR}\n"
        printf "${YELLOW}What Base Domain should be used for your ClusterPool Clusters (ex. mydomain.com)?${CLEAR} "
        read CLUSTERPOOL_GCP_BASE_DOMAIN
    fi
    printf "${GREEN}* Using GCP Base Domain ${CLUSTERPOOL_GCP_BASE_DOMAIN}${CLEAR}\n"
else
    printf "${RED}Unsupported platform ${PLATFORM} detected, secret creation wizard only supports AWS, AZURE, and GCP.  Exiting.${CLEAR}\n"
    exit 3
fi


#----GET CLUSTERPOOL SIZE----#
if [[ "$CLUSTERPOOL_SIZE" == "" ]]; then
    printf "${BLUE}- note: to skip this step in the future, export CLUSTERPOOL_SIZE${CLEAR}\n"
    printf "${YELLOW}How many clusters would you like in your pool (note: this is the number of clusters the pool will keep live and waiting)?${CLEAR} "
    read CLUSTERPOOL_SIZE
fi
printf "${GREEN}* Using Size: $CLUSTERPOOL_SIZE${CLEAR}\n"


#----GET THE CLUSTERPOOL'S NAME----#
if [[ "$CLUSTERPOOL_NAME" == "" ]]; then
    printf "${BLUE}- note: to skip this step in the future, export CLUSTERPOOL_NAME${CLEAR}\n"
    printf "${YELLOW}What would you like to name your ClusterPool  Press enter or export CLUSTERPOOL_NAME="" to use our generated name ($GENERATED_CLUSTERPOOL_NAME-$CLUSTERIMAGESET_NAME)?${CLEAR} "
    read INPUT_CLUSTERPOOL_NAME
    if [[ "$INPUT_CLUSTERPOOL_NAME" == "" ]]; then
        CLUSTERPOOL_NAME="$GENERATED_CLUSTERPOOL_NAME-$(echo $PLATFORM | tr '[:upper:]' '[:lower:]')-$CLUSTERIMAGESET_NAME"
    else
        CLUSTERPOOL_NAME="$INPUT_CLUSTERPOOL_NAME"
    fi
fi
printf "${GREEN}* Using Name: $CLUSTERPOOL_NAME${CLEAR}\n"


#-----BUILD THE CLUSTERPOOL YAML-----#
printf "\n${GREEN}#### Generating yaml and Creating ClusterPools"
if [[ ! -d ./${CLUSTERPOOL_NAME} ]]; then
    mkdir ./${CLUSTERPOOL_NAME}
fi
if [[ "$PLATFORM" == "AWS" ]]; then
    ${SED} -e "s/__CLUSTERPOOL_NAME__/$CLUSTERPOOL_NAME/g" \
           -e "s/__TARGET_NAMESPACE__/$TARGET_NAMESPACE/g" \
           -e "s/__CLUSTERPOOL_AWS_BASE_DOMAIN__/$CLUSTERPOOL_AWS_BASE_DOMAIN/g" \
           -e "s/__CLUSTERIMAGESET_NAME__/$CLUSTERIMAGESET_NAME/g" \
           -e "s/__CLUSTERPOOL_SIZE__/$CLUSTERPOOL_SIZE/g" \
           -e "s/__OCP_PULL_SECRET__/$OCP_PULL_SECRET/g" \
           -e "s/__CLOUD_CREDENTIAL_SECRET__/$CLOUD_CREDENTIAL_SECRET/g" \
           -e "s/__CLUSTERPOOL_AWS_REGION__/$CLUSTERPOOL_AWS_REGION/g" ./templates/clusterpool.aws.yaml.template > ./${CLUSTERPOOL_NAME}/${CLUSTERPOOL_NAME}.clusterpool.yaml
elif [[ "$PLATFORM" == "AZURE" ]]; then
    ${SED} -e "s/__CLUSTERPOOL_NAME__/$CLUSTERPOOL_NAME/g" \
           -e "s/__TARGET_NAMESPACE__/$TARGET_NAMESPACE/g" \
           -e "s/__CLUSTERPOOL_AZURE_BASE_DOMAIN__/$CLUSTERPOOL_AZURE_BASE_DOMAIN/g" \
           -e "s/__CLUSTERIMAGESET_NAME__/$CLUSTERIMAGESET_NAME/g" \
           -e "s/__CLUSTERPOOL_SIZE__/$CLUSTERPOOL_SIZE/g" \
           -e "s/__OCP_PULL_SECRET__/$OCP_PULL_SECRET/g" \
           -e "s/__CLOUD_CREDENTIAL_SECRET__/$CLOUD_CREDENTIAL_SECRET/g" \
           -e "s/__CLUSTERPOOL_AZURE_BASE_DOMAIN_RESOURCE_GROUP_NAME__/$CLUSTERPOOL_AZURE_BASE_DOMAIN_RESOURCE_GROUP_NAME/g" \
           -e "s/__CLUSTERPOOL_AZURE_REGION__/$CLUSTERPOOL_AZURE_REGION/g" ./templates/clusterpool.azure.yaml.template > ./${CLUSTERPOOL_NAME}/${CLUSTERPOOL_NAME}.clusterpool.yaml
elif [[ "$PLATFORM" == "GCP" ]]; then
    ${SED} -e "s/__CLUSTERPOOL_NAME__/$CLUSTERPOOL_NAME/g" \
           -e "s/__TARGET_NAMESPACE__/$TARGET_NAMESPACE/g" \
           -e "s/__CLUSTERPOOL_GCP_BASE_DOMAIN__/$CLUSTERPOOL_GCP_BASE_DOMAIN/g" \
           -e "s/__CLUSTERIMAGESET_NAME__/$CLUSTERIMAGESET_NAME/g" \
           -e "s/__CLUSTERPOOL_SIZE__/$CLUSTERPOOL_SIZE/g" \
           -e "s/__OCP_PULL_SECRET__/$OCP_PULL_SECRET/g" \
           -e "s/__CLOUD_CREDENTIAL_SECRET__/$CLOUD_CREDENTIAL_SECRET/g" \
           -e "s/__CLUSTERPOOL_GCP_REGION__/$CLUSTERPOOL_GCP_REGION/g" ./templates/clusterpool.gcp.yaml.template > ./${CLUSTERPOOL_NAME}/${CLUSTERPOOL_NAME}.clusterpool.yaml
else
    printf "${RED}Unsupported platform ${PLATFORM} detected, secret creation wizard only supports AWS, AZURE, and GCP.  Exiting.${CLEAR}"
    exit 3
fi

#-----APPLY THE CLUSTERPOOL YAML-----#
printf "${GREEN} Applying the following yaml to create your ClusterPool (./${CLUSTERPOOL_NAME}/${CLUSTERPOOL_NAME}.clusterpool.yaml):\n${CLEAR}"
printf "${BLUE}"
cat ./${CLUSTERPOOL_NAME}/${CLUSTERPOOL_NAME}.clusterpool.yaml
printf "${CLEAR}\n"
oc apply -f ./${CLUSTERPOOL_NAME}/${CLUSTERPOOL_NAME}.clusterpool.yaml
if [[ "$?" -ne 0 ]]; then
    printf "${RED}Failed to create ClusterPool $CLUSTERPOOL_NAME, see above error message for more detail.${CLEAR}\n"
    exit 3
fi
