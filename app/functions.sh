error() {
    if [ "$LOG_TO_FILE" == "true" ];then
        local logFile=$CURRENT_LOG_FILE
        create_junit_report
        echo >&2 -e "\e[41mError: see log file $logFile\e[0m"
    fi

    local parent_lineno="$1"
    local message="$2"
    local code="${3:-1}"
    local line_message=""
    if [ "$parent_lineno" != "" ]; then
        line_message="on or near line ${parent_lineno}"
    fi

    if [[ -n "$message" ]]; then
        echo >&2 -e "\e[41mError $line_message: ${message}; exiting with status ${code}\e[0m"
    else
        echo >&2 -e "\e[41mError $line_message; exiting with status ${code}\e[0m"
    fi
    echo ""

    clean_up_variables

    exit ${code}
}

function export_azure_cloud_env {
    local tf_cloud_env=''

    # Set cloud variables for terraform
    unset AZURE_ENVIRONMENT
    unset ARM_ENVIRONMENT
    export AZURE_ENVIRONMENT=$(az cloud show --query name -o tsv)

    if [ -z "$cloud_name" ]; then

        case $AZURE_ENVIRONMENT in
        AzureCloud)
            tf_cloud_env='public'
            ;;
        AzureChinaCloud)
            tf_cloud_env='china'
            ;;
        AzureUSGovernment)
            tf_cloud_env='usgovernment'
            ;;
        AzureGermanCloud)
            tf_cloud_env='german'
            ;;
        esac

        export ARM_ENVIRONMENT=$tf_cloud_env
    else
        export ARM_ENVIRONMENT=$cloud_name
    fi

    echo " - AZURE_ENVIRONMENT: ${AZURE_ENVIRONMENT}"
    echo " - ARM_ENVIRONMENT: ${ARM_ENVIRONMENT}"

    # Set landingzone cloud variables for modules
    echo "Initalizing az cloud variables"
    while IFS="=" read key value; do
        log_debug " - TF_VAR_$key = $value"
        export "TF_VAR_$key=$value"
    done < <(az cloud show | jq -r ".suffixes * .endpoints|to_entries|map(\"\(.key)=\(.value)\")|.[]")
}

function get_logged_user_object_id {
    echo "@calling_get_logged_user_object_id"

    export TF_VAR_user_type=$(az account show \
        --query user.type -o tsv)

    export_azure_cloud_env

    if [ ${TF_VAR_user_type} == "user" ]; then

        unset ARM_TENANT_ID
        unset ARM_SUBSCRIPTION_ID
        unset ARM_CLIENT_ID
        unset ARM_CLIENT_SECRET
        unset TF_VAR_logged_aad_app_objectId

        export ARM_TENANT_ID=$(az account show -o json | jq -r .tenantId)
        export TF_VAR_logged_user_objectId=$(az ad signed-in-user show --query objectId -o tsv)
        export logged_user_upn=$(az ad signed-in-user show --query userPrincipalName -o tsv)
        echo " - logged in user objectId: ${TF_VAR_logged_user_objectId} (${logged_user_upn})"

        echo "Initializing state with user: $(az ad signed-in-user show --query userPrincipalName -o tsv)"
    else
        unset TF_VAR_logged_user_objectId
        export clientId=$(az account show --query user.name -o tsv)

        export keyvault=$(az keyvault list --subscription ${TF_VAR_tfstate_subscription_id} --query "[?tags.tfstate=='${TF_VAR_level}' && tags.environment=='${TF_VAR_environment}']" -o json | jq -r .[0].name)

        case "${clientId}" in
            "systemAssignedIdentity")
                if [ -z ${MSI_ID} ]; then
                    computerName=$(az rest --method get --headers Metadata=true --url http://169.254.169.254/metadata/instance?api-version=2020-09-01 | jq -r .compute.name)
                    principalId=$(az resource list -n ${computerName} --query [*].identity.principalId --out tsv)
                    echo " - logged in Azure with System Assigned Identity - computer name - ${computerName}"
                    export TF_VAR_logged_user_objectId=${principalId}
                    export ARM_TENANT_ID=$(az account show | jq -r .tenantId)
                else
                    echo " - logged in Azure with System Assigned Identity - ${MSI_ID}"
                    export TF_VAR_logged_user_objectId=$(az identity show --ids ${MSI_ID} --query principalId -o tsv)
                    export ARM_TENANT_ID=$(az identity show --ids ${MSI_ID} --query tenantId -o tsv)
                fi
                ;;
            "userAssignedIdentity")
                msi=$(az account show | jq -r .user.assignedIdentityInfo)
                echo " - logged in Azure with User Assigned Identity: ($msi)"
                msiResource=$(get_resource_from_assignedIdentityInfo "$msi")
                export TF_VAR_logged_aad_app_objectId=$(az identity show --ids $msiResource | jq -r .principalId)
                export TF_VAR_logged_user_objectId=$(az identity show --ids $msiResource | jq -r .principalId) && echo " Logged in rover msi object_id: ${TF_VAR_logged_user_objectId}"
                export ARM_CLIENT_ID=$(az identity show --ids $msiResource | jq -r .clientId)
                export ARM_TENANT_ID=$(az identity show --ids $msiResource | jq -r .tenantId)
                ;;
            *)
                # When connected with a service account the name contains the objectId
                export TF_VAR_logged_aad_app_objectId=$(az ad sp show --id ${clientId} --query objectId -o tsv) && echo " Logged in rover app object_id: ${TF_VAR_logged_aad_app_objectId}"
                export TF_VAR_logged_user_objectId=$(az ad sp show --id ${clientId} --query objectId -o tsv) && echo " Logged in rover app object_id: ${TF_VAR_logged_aad_app_objectId}"
                echo " - logged in Azure AD application:  $(az ad sp show --id ${clientId} --query displayName -o tsv)"
                ;;
        esac

    fi

    export TF_VAR_tenant_id=${ARM_TENANT_ID}
}

get_logged_user_object_id