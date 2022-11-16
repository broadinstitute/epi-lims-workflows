PROJECT=$(gcloud config get-value project)
echo $PROJECT

# # TODO: replace broad-epi-dev with this variable
# PROJECT=$(gcloud config get-value project)
# REGION="us-east1"
# COLLECTION="broad-epi-dev-beta2"
# # TODO create the Cromwell SA?
# # TODO make sure cloudbuild has SA User permissions for this SA?
# CROMWELL_SA="lims-cromwell-user@broad-epi-dev.iam.gserviceaccount.com"

# # Get cloudbuild SA token
# TOKEN=$(gcloud auth print-access-token)

# # Get an auth token for the Cromwell SA
# CROMWELL_SA_TOKEN=$(curl -sH "Authorization: Bearer ${TOKEN}" \
#   "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${CROMWELL_SA}:generateAccessToken" \
#   -H "Content-Type: application/json" \
#   -d "{
#     \"scope\": [
#         \"https://www.googleapis.com/auth/userinfo.email\",
#         \"https://www.googleapis.com/auth/userinfo.profile\"
#     ]
#   }" \
#   | python3 -c 'import json,sys; print(json.load(sys.stdin)["accessToken"])')

# # Register the SA with Sam
# curl -sH "Authorization: Bearer ${CROMWELL_SA_TOKEN}" "https://sam.dsde-prod.broadinstitute.org/register/user/v1" -d ""

# # Allow SA to start workflows in the collection
# curl -sH "Authorization: Bearer ${TOKEN}" -X PUT "https://sam.dsde-prod.broadinstitute.org/api/resources/v1/workflow-collection/${COLLECTION}/policies/writer" -H "Content-Type: application/json" -d "{\"memberEmails\": [\"${CROMWELL_SA}\"], \"roles\": [\"writer\"], \"actions\": []}"
 
# # Create key for SA 
# CROMWELL_SA_KEY=$(gcloud iam service-accounts keys create /dev/stdout --iam-account "${CROMWELL_SA}")

# # Deploy Cromwell launcher function, passing in key as environment variable
# # TODO non-destructively use --update-env-vars instead?
# gcloud functions deploy python-http-function \
#     --gen2 \
#     --runtime=python310 \
#     --region=$REGION \
#     --source=. \
#     --entry-point=launch_cromwell \
#     --trigger-http \
#     --allow-unauthenticated
#     --set-env-vars KEY=$CROMWELL_SA_KEY

# # NOTE: Could also store key in runtime config so that functions can access it
# # gcloud beta runtime-config configs variables set --config-name=cromwell-config cromwell-key $CROMWELL_SA_KEY

# # Deploy Cromwell parser functions
# # TODO