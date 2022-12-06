#!/bin/bash

set -euo pipefail

# TODO: replace broad-epi-dev with this variable - access _ENV from cloudbuild vars
PROJECT=$(gcloud config get-value project)
# TODO: replace 667661088669 with this variable
PROJECT_NUMBER=$(gcloud projects list --filter="project_id:$PROJECT" --format='value(project_number)')
REGION="us-east1"
# TODO should be broad-epi-beta2 for prod
COLLECTION="broad-epi-dev-beta2"

# The Cromwell endpoint where jobs are submitted
CROMWELL_ENDPOINT="https://cromwell.caas-prod.broadinstitute.org/api/workflows/v1"

# The SA that allows us to call external services such as Sam
CLOUDBUILD_SA="cloudbuild@broad-epi-dev.iam.gserviceaccount.com"

# The SA that will be used to launch Cromwell jobs
CROMWELL_SA="lims-cromwell-user@broad-epi-dev.iam.gserviceaccount.com"

# The default SA identity used by 2nd gen cloud functions
FUNCTION_SA="667661088669-compute@developer.gserviceaccount.com"

# The SA for Google Cloud Storage
GCS_SA=$(gsutil kms serviceaccount -p $PROJECT_NUMBER)

# Use local google identity, the default cloudbuild service account
    # <project_id>@cloudbuild.gserviceaccount.com
TOKEN=$(gcloud auth print-access-token)

# Name of Runtime Config where we store variables accessible to cloud functions
CONFIG="lims-cromwell-config"

# Name of key where the Cromwell SA credentials are stored in the Runtime Config
CONFIG_KEY="cromwell-sa-key"

# TODO change firebase key to a new one
# Name and location of the KMS key used to encrypt/decrypt the Cromwell SA creds
KMS_KEY="firebase"
KMS_LOCATION="global"

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
# TODO use google account ID var and replace cloudbuild SA with var
gcloud iam service-accounts add-iam-policy-binding $FUNCTION_SA \
    --member serviceAccount:667661088669@cloudbuild.gserviceaccount.com \
    --role roles/iam.serviceAccountUser

# Enable GCS SA to use Pub/Sub for GCF triggers
gcloud projects add-iam-policy-binding broad-epi-dev \
    --member="serviceAccount:${GCS_SA}" \
    --role='roles/pubsub.publisher'

# Enable required GCP APIs
# gcloud services enable \
#     pubsub.googleapis.com \
#     cloudbuild.googleapis.com \
#     logging.googleapis.com \
#     eventarc.googleapis.com \
#     artifactregistry.googleapis.com \
#     run.googleapis.com \
#     --quiet

# if no key exists for the Cromwell SA, create one, encrypt it
# using KMS, and store it in the Runtime Config. This key is
# required for Cromwell auth in order to submit jobs, and is
# retrieved by the launch_cromwell cloud function

set_config() {
  gcloud beta runtime-config configs variables set --config-name "$1" "$2" --is-text
}

encrypt() {
  gcloud kms encrypt \
    --location $KMS_LOCATION \
    --keyring $KMS_KEY \
    --key $KMS_KEY \
    --plaintext-file - \
    --ciphertext-file -
}

# first make sure there's a runtime config
if [ -z "$(gcloud beta runtime-config configs list | grep $CONFIG)" ]; then
  gcloud beta runtime-config configs create $CONFIG
else
  echo "Runtime Config already exists"
fi

# check if key exists
CURRENT_KEY=$(gcloud iam service-accounts keys list \
    --iam-account "${CROMWELL_SA}" \
    --managed-by user \
    --limit 1)

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

ENCRYPTED_KEY=$(gcloud beta runtime-config configs variables \
  get-value "${CONFIG_KEY}" \
  --config-name "${CONFIG}")

# Deploy Cromwell launcher function, passing encrypted key
# as env variable
gcloud functions deploy cromwell-launcher \
    --gen2 \
    --runtime=python310 \
    --region=$REGION \
    --source=. \
    --entry-point=launch_cromwell \
    --trigger-http \
    --allow-unauthenticated \
    --set-env-vars KEY=$ENCRYPTED_KEY,KMS_KEY=$KMS_KEY,KMS_LOCATION=$KMS_LOCATION,PROJECT=$PROJECT,ENDPOINT=$CROMWELL_ENDPOINT

echo "Deployed Cromwell launcher function"

# Give permissions to cloud function SA so that it can interact
# with GCS, EventArc, and PubSub, all used for the GCF trigger
# functions that receive outputs from Cromwell and write to LIMS
gsutil iam ch allUsers:objectViewer gs://broad-epi-dev-morgane-test

gcloud projects add-iam-policy-binding $PROJECT \
  --member serviceAccount:$SERVICE_ACCOUNT \
  --role roles/pubsub.publisher

gcloud projects add-iam-policy-binding $PROJECT \
  --member "serviceAccount:667661088669-compute@developer.gserviceaccount.com" \
  --role "roles/artifactregistry.reader"

gcloud projects add-iam-policy-binding $PROJECT \
  --member "serviceAccount:667661088669-compute@developer.gserviceaccount.com" \
  --role "roles/storage.objectCreator"

gcloud projects add-iam-policy-binding $PROJECT \
  --member "serviceAccount:667661088669-compute@developer.gserviceaccount.com" \
  --role "roles/run.invoker"

gcloud projects add-iam-policy-binding $PROJECT \
  --member "serviceAccount:667661088669-compute@developer.gserviceaccount.com" \
  --role "roles/eventarc.eventReceiver"

# Get LIMS username/password
LIMS_SECRET=$(gcloud secrets versions access 1 --secret lims-api-user)
LIMS_USERNAME=$(echo $LIMS_SECRET | cut -d',' -f1)
LIMS_PASSWORD=$(echo $LIMS_SECRET | cut -d',' -f2)

# Deploy Cromwell parser functions. These use GCP's EventArc API,
# which needs to be enabled for these functions to build. These
# functions are triggered when the trigger-bucket is updated using
# Pub/Sub. This automatically creates an EventArc trigger and
# Pub/Sub subscription
gcloud functions deploy on-chipseq-done \
    --gen2 \
    --runtime=python310 \
    --region=$REGION \
    --source=. \
    --entry-point=on_chipseq_done \
    --trigger-bucket="gs://broad-epi-dev-morgane-test" \
    --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
    --service-account=$FUNCTION_SA \
    --set-env-vars PROJECT=$PROJECT,LIMS_USERNAME=$LIMS_USERNAME,LIMS_PASSWORD=$LIMS_PASSWORD
# TODO add retry flag? https://cloud.google.com/functions/docs/bestpractices/retries