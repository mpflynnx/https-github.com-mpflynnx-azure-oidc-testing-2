#!/usr/bin/env bash

DEBUG=${DEBUG:-"NO"}
# Set to "YES" to send error output to the console:

[ "$DEBUG" = "NO" ] && DBGOUT="/dev/null" || DBGOUT="/dev/stderr"


cleanup() {
  # Clean up by unmounting our loopmounts, deleting tempfiles:
  echo "--- Cleaning up ..."
  rm .env 2>${DBGOUT} || true
#   rm credential.json 2>${DBGOUT} || true

}
trap 'echo "*** $0 FAILED at line $LINENO ***"; cleanup; exit 1' ERR INT TERM

# create new repo from static-website-azure-oidc template
# login to gh cli locally
# clone repo locally

# do I run this scipt as a service principal?
# login to az cli
# run this script
# this script depends on gh cli, az cli

OWNER=$(gh repo view --json owner -q ".owner.login")

# Repository name is the appName!
APP_NAME=$(gh repo view --json name -q ".name")

ROLE="Contributor"
AZURE_TENANT_ID=$(az account show --query "tenantId" --output tsv)
AZURE_SUBSCRIPTION_ID=$(az account show --query "id" --output tsv)
#resourceGroupName="OpenID_Connect_Testing_Nov2023"

# is this really required?
#az account set -s $AZURE_SUBSCRIPTION_ID

# Create the Microsoft Entra application.
az ad app create --display-name ${APP_NAME}

# New Service principal
CLIENT_ID=$(az ad app list --display-name ${APP_NAME} --query "[].appId" --output tsv)

az ad sp create --id ${CLIENT_ID}

# ObjectId of the service principal
SP_OBJECT_ID=$(az ad sp list --display-name ${APP_NAME} --query "[].id" --output tsv)

# Add role assignment
# not working with --scope as of November 2023
az role assignment create --role ${ROLE} --subscription ${AZURE_SUBSCRIPTION_ID} --assignee-object-id ${SP_OBJECT_ID} --assignee-principal-type ServicePrincipal

# create a new federated identity credential
# https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust?pivots=identity-wif-apps-methods-azcli
# https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust?pivots=identity-wif-apps-methods-azp

#needs object id of the app registration not service principal
APP_OBJECT_ID=$(az ad app list --display-name ${APP_NAME} --query "[].id" --output tsv)
#6295ef69-4a7a-4264-8ab2-0e6891f22ab6

# create credential.json using heredoc
cat > "credential.json" << EOF
{
    "name": "${APP_NAME}",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:${OWNER}/${APP_NAME}:ref:refs/heads/main",
    "description": "${APP_NAME}",
    "audiences": [
        "api://AzureADTokenExchange"
    ]
}
EOF

az ad app federated-credential create --id ${APP_OBJECT_ID} --parameters credential.json

# alternative described here:
# https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blobs-static-site-github-actions?tabs=openid#generate-deployment-credentials
#az rest --method POST --uri 'https://graph.microsoft.com/beta/applications/<APPLICATION-OBJECT-ID>/federatedIdentityCredentials' --body '{"name":"<CREDENTIAL-NAME>","issuer":"https://token.actions.githubusercontent.com","subject":"repo:organization/repository:ref:refs/heads/main","description":"Testing","audiences":["api://AzureADTokenExchange"]}'

# search Default Directory | App registrations
# static-website-github-action-oidc | Certificates & secrets

# to run this file ./new-entra-app.sh

#echo "Application Client ID: $CLIENT_ID"

# set clientId as environmental variable or create .env file if multiple
# needed

# set up github cli

# gh cli secret set
#https://www.thegeekdiary.com/gh-secret-manage-github-secrets-from-the-command-line/

#set secrets using gh cli from the $ENV_VALUE
#gh secret set MYSECRET --body "$ENV_VALUE"

#OR


# use heredoc

cat > ".env" << EOF
AZURE_CLIENT_ID=${CLIENT_ID}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
EOF

# Set multiple secrets imported from the ".env" file must make sure
# .env is not part of VCS i.e .gitignore
gh secret set -f .env


# cleanup

