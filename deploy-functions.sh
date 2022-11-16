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

# Create a key for Cromwell SA, used for launching Cromwell jobs
CROMWELL_SA_KEY=$(gcloud iam service-accounts keys create /dev/stdout --iam-account "${CROMWELL_SA}") \
  | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)))'

# Deploy Cromwell launcher function, passing in key as environment variable
# TODO non-destructively use --update-env-vars instead?
gcloud functions deploy python-http-function \
    --gen2 \
    --runtime=python310 \
    --region=$REGION \
    --source=. \
    --entry-point=launch_cromwell \
    --trigger-http \
    --allow-unauthenticated \
    --set-env-vars KEY=$CROMWELL_SA_KEY

echo "Deployed Cromwell launcher function"

# NOTE: Could also store key in runtime config so that functions can access it
# gcloud beta runtime-config configs variables set --config-name=cromwell-config cromwell-key $CROMWELL_SA_KEY

# Deploy Cromwell parser functions
# TODO