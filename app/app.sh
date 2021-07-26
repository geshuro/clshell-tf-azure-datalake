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

export TF_VAR_region="westus2"