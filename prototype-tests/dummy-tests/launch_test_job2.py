import io
import json
import requests
# import google.auth.transport.requests
# from google.oauth2 import service_account

def download(url):
    response = requests.get(url)
    response.raise_for_status()
    response_str = response.text.encode('utf-8')
    return response_str

endpoint = 'https://cromwell.caas-prod.broadinstitute.org/api/workflows/v1'
sa_key = json.load(open('keys/cloudbuild_sa_key-dev.json', 'r'))
client_email = sa_key['client_email']

# credentials = service_account.Credentials.from_service_account_info(
#     sa_key,
#     scopes=['email', 'openid', 'profile']
# )
# if not credentials.valid:
#     credentials.refresh(google.auth.transport.requests.Request())
# header = {}
# credentials.apply(header)

workflow_inputs = io.BytesIO(json.dumps({
    "helloWorld": "hello world, from morgane"
}).encode())

workflow_options = io.BytesIO(json.dumps({
    "backend": "PAPIv2",
    "google_project": "broad-epi-dev",
    "jes_gcs_root": "gs://broad-epi-dev-cromwell/workflows",
    "monitoring_image": "us.gcr.io/broad-epi-dev/cromwell-task-monitor-bq",
    "final_workflow_log_dir": "gs://broad-epi-dev-cromwell-logs",
    "user_service_account_json": json.dumps(sa_key),
    "google_compute_service_account": client_email,
    "default_runtime_attributes": {
        "disks": "local-disk 10 HDD",
        "maxRetries": 1,
        "preemptible": 3,
        "zones": [
            "us-east1-b",
            "us-east1-c",
            "us-east1-d"
        ]
    }
}).encode())

submission_manifest = {
	'workflowUrl': 'https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/lims_test.wdl',
	'workflowInputs': workflow_inputs,
	'collectionName': 'broad-epi-dev-beta2',
	'workflowOnHold': False,
	'workflowOptions': workflow_options
}

response = requests.post(
	endpoint,
    data=submission_manifest,
    auth=None,
    headers={'authorization': ''}
)
print(response.text)
