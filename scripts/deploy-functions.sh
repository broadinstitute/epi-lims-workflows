#!/bin/bash

set -euo pipefail

# TODO: replace broad-epi-dev with this variable - access _ENV from cloudbuild vars
PROJECT=$(gcloud config get-value project)
REGION="us-east1"
COLLECTION="broad-epi-dev-beta2"
# TODO create the Cromwell SA?
# TODO make sure cloudbuild has SA User permissions for this SA?
CLOUDBUILD_SA="cloudbuild@broad-epi-dev.iam.gserviceaccount.com"
CROMWELL_SA="lims-cromwell-user@broad-epi-dev.iam.gserviceaccount.com"

# Use local cloudbuild google identity to authenticate to IAM API
echo "Getting local token"
TOKEN=$(gcloud auth print-access-token)
echo $TOKEN

echo "Getting Cromwell SA token"
CROMWELL_SA_TOKEN=$(curl -sH "Authorization: Bearer ${TOKEN}" \
  "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${CROMWELL_SA}:generateAccessToken" \
  -H "Content-Type: application/json" \
  -d "{
    \"scope\": [
        \"https://www.googleapis.com/auth/userinfo.email\",
        \"https://www.googleapis.com/auth/userinfo.profile\"
    ]
  }" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["accessToken"])')
echo $CROMWELL_SA_TOKEN

# Register the Cromwell SA with Sam
echo "Registering Cromwell SA with Sam"
curl -sH "Authorization: Bearer ${CROMWELL_SA_TOKEN}" "https://sam.dsde-prod.broadinstitute.org/register/user/v1" -d ""

# Get an auth token for cloudbuild SA
echo "Getting cloudbuild SA token"
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
echo $CLOUDBUILD_TOKEN

# Allow SA to start workflows in the dev collection
echo "Allow Cromwell SA to start workflows in collection"
curl -sH "Authorization: Bearer ${CLOUDBUILD_TOKEN}" -X PUT "https://sam.dsde-prod.broadinstitute.org/api/resources/v1/workflow-collection/${COLLECTION}/policies/writer" -H "Content-Type: application/json" -d "{\"memberEmails\": [\"${CROMWELL_SA}\"], \"roles\": [\"writer\"], \"actions\": []}"

# Deploy Cromwell launcher function, passing in key as environment variable
# TODO non-destructively use --update-env-vars instead?
echo "Deploy function"
gcloud functions deploy python-http-function \
    --gen2 \
    --runtime=python310 \
    --region=$REGION \
    --source=. \
    --entry-point=launch_cromwell \
    --trigger-http \
    --allow-unauthenticated
    --set-env-vars KEY=$CROMWELL_SA_KEY

echo "Deployed Cromwell launcher function"

# NOTE: Could also store key in runtime config so that functions can access it
# gcloud beta runtime-config configs variables set --config-name=cromwell-config cromwell-key $CROMWELL_SA_KEY

# Deploy Cromwell parser functions
# TODO