#!/usr/bin/env bash

DEBUG=${DEBUG:-"NO"}
# Set to "YES" to send error output to the console:

[ "$DEBUG" = "NO" ] && DBGOUT="/dev/null" || DBGOUT="/dev/stderr"


cleanup() {
  # Clean up by deleting tempfiles:
  echo "--- Cleaning up ..."
  rm .env 2>${DBGOUT} || true
  rm credential.json 2>${DBGOUT} || true

}
trap 'echo "*** $0 FAILED at line $LINENO ***"; cleanup; exit 1' ERR INT TERM

# AZ CLI check
echo "Making sure you're signed in to Azure CLI..."
az account show -o none

if [ ! $? -eq 0 ]
then
    exit 1
fi

echo "Using the following Azure subscription. If this isn't correct, press Ctrl+C and select the correct subscription with \"az account set\""
echo "${newline}"
az account show -o table
echo "${newline}"

# GitHub CLI check
echo "Making sure you're signed in to GitHub CLI..."
gh auth status

if [ ! $? -eq 0 ]
then
    exit 1
fi

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

# check for existing app first
CLIENT_ID=$(az ad app list --display-name ${APP_NAME} --query "[].appId" --output tsv)

if [ ! -z "$CLIENT_ID" ]
then
  echo "Application ${APP_NAME} already exists, exiting."
  exit 1
fi

# Create a Microsoft Entra application.
echo "Creating new Microsoft Entra application...."
az ad app create --display-name ${APP_NAME}
CLIENT_ID=$(az ad app list --display-name ${APP_NAME} --query "[].appId" --output tsv)
echo "Application Created."

# Create new Service principal
echo "Creating new Enterprise Application...."
if [ ! -z "$CLIENT_ID" ]
then
  az ad sp create --id ${CLIENT_ID}
fi

# Get ObjectId of the service principal
SP_OBJECT_ID=$(az ad sp list --display-name ${APP_NAME} --query "[].id" --output tsv)

# Add role assignment
# not working with --scope as of November 2023
if [ ! -z "SP_OBJECT_ID" ]
then
  az role assignment create \
    --role ${ROLE} \
    --subscription ${AZURE_SUBSCRIPTION_ID} \
    --assignee-object-id ${SP_OBJECT_ID} \
    --assignee-principal-type ServicePrincipal \
    --output none
fi

# Create a new federated identity credential
# Needs object id of the app registration not service principal
APP_OBJECT_ID=$(az ad app list --display-name ${APP_NAME} --query "[].id" --output tsv)

# Create credential.json using Heredoc
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

echo "Adding federated credentials...."
if [ ! -z "APP_OBJECT_ID" ]
then
  az ad app federated-credential create --id ${APP_OBJECT_ID} --parameters credential.json
fi

# Use Heredoc to create a .env file
cat > ".env" << EOF
AZURE_CLIENT_ID=${CLIENT_ID}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
EOF

# Set multiple secrets imported from the ".env" file must make sure
# .env is not part of VCS i.e .gitignore
echo "Adding repository GitHub secrets to be referenced in your workflow...."

gh secret set -f .env

cleanup
