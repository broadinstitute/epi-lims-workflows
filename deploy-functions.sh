#!/bin/bash

set -euo pipefail

# TODO: replace broad-epi-dev with this variable - access _ENV from cloudbuild vars
PROJECT=$(gcloud config get-value project)
REGION="us-east1"
COLLECTION="broad-epi-dev-beta2"

# The SA that allows us to call external services such as Sam
CLOUDBUILD_SA="cloudbuild@broad-epi-dev.iam.gserviceaccount.com"

# The SA that will be used to launch Cromwell jobs
CROMWELL_SA="lims-cromwell-user@broad-epi-dev.iam.gserviceaccount.com"

# Use local google identity, the default cloudbuild service account
    # <project_id>@cloudbuild.gserviceaccount.com
TOKEN=$(gcloud auth print-access-token)

# Name of Runtime Config where we store variables accessible to cloud functions
CONFIG="lims-cromwell-config"

# Name of key where the Cromwell SA credentials are stored in the Runtime Config
CONFIG_KEY="cromwell-sa-key"

# Get auth token for Cromwell SA
CROMWELL_TOKEN=$(curl -sH "Authorization: Bearer ${TOKEN}" \
  "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${CROMWELL_SA}:generateAccessToken" \
  -H "Content-Type: application/json" \
  -d "{
    \"scope\": [
        \"https://www.googleapis.com/auth/userinfo.email\",
        \"https://www.googleapis.com/auth/userinfo.profile\"
    ]
  }" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["accessToken"])')

# Register the Cromwell SA with Sam
curl -sH "Authorization: Bearer ${CROMWELL_TOKEN}" "https://sam.dsde-prod.broadinstitute.org/register/user/v1" -d ""

# Get an auth token for cloudbuild SA
CLOUDBUILD_TOKEN=$(curl -sH "Authorization: Bearer ${TOKEN}" \
  "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${CLOUDBUILD_SA}:generateAccessToken" \
  -H "Content-Type: application/json" \
  -d "{
    \"scope\": [
        \"https://www.googleapis.com/auth/userinfo.email\",
        \"https://www.googleapis.com/auth/userinfo.profile\"
    ]
  }" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["accessToken"])')

# Allow SA to start workflows in the dev collection
curl -sH "Authorization: Bearer ${CLOUDBUILD_TOKEN}" -X PUT "https://sam.dsde-prod.broadinstitute.org/api/resources/v1/workflow-collection/${COLLECTION}/policies/writer" -H "Content-Type: application/json" -d "{\"memberEmails\": [\"${CROMWELL_SA}\"], \"roles\": [\"writer\"], \"actions\": []}"

# TODO add comment for this
# TODO use google account ID var
gcloud iam service-accounts add-iam-policy-binding \
    667661088669-compute@developer.gserviceaccount.com \
    --member serviceAccount:667661088669@cloudbuild.gserviceaccount.com \
    --role roles/iam.serviceAccountUser

# if no key exists for the Cromwell SA, create one, encrypt it
# using KMS, and store it in the Runtime Config. This key is
# required for Cromwell auth in order to submit jobs, and is
# retrieved by the launch_cromwell cloud function

# first make sure there's a runtime config
if [ -z "$(gcloud beta runtime-config configs list | grep $CONFIG)" ]; then
  gcloud beta runtime-config configs create $CONFIG
else
  echo "Runtime Config already exists"
fi

set_config() {
  gcloud beta runtime-config configs variables set --config-name "$1" "$2" --is-text
}

# TODO change firebase key to a new one
encrypt() {
  gcloud kms encrypt \
    --location "global" \
    --keyring "firebase" \
    --key "firebase" \
    --plaintext-file - \
    --ciphertext-file -
}

# check if key exists
CURRENT_KEY=$(gcloud iam service-accounts keys list \
    --iam-account "${CROMWELL_SA}" \
    --managed-by user \
    --limit 1)

echo "Current key"
echo $CURRENT_KEY

# if it doesn't exist, encrypt it and store it in the cromwell
# config as a key-value pair indexed by "cromwell-sa-key"
if [ -z "${CURRENT_KEY}" ]; then
  echo "Creating new Cromwell SA credentials file"
  gcloud iam service-accounts keys create /dev/stdout \
    --iam-account "${CROMWELL_SA}" \
    | encrypt \
    | base64 -w 0 \
    | set_config $CONFIG $CONFIG_KEY
else
  echo "Cromwell credentials already exist"
fi

# Deploy Cromwell launcher function
gcloud functions deploy cromwell-launcher \
    --gen2 \
    --runtime=python310 \
    --region=$REGION \
    --source=. \
    --entry-point=launch_cromwell \
    --trigger-http \
    --allow-unauthenticated \
    --set-env-vars CONFIG=$CONFIG,KEY=$CONFIG_KEY

echo "Deployed Cromwell launcher function"

# Deploy Cromwell parser functions
# TODO