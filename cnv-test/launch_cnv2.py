import io
import json
import requests

endpoint = 'https://cromwell.caas-prod.broadinstitute.org/api/workflows/v1'
sa_key = json.load(open('../keys/cromwell_user_sa_key-dev.json', 'r'))
client_email = sa_key['client_email']

workflow_inputs = io.BytesIO(json.dumps({
    "CNVAnalysis.bam": "gs://broad-epi-dev-aggregated-alns/aggregated_aln_028227.bam",
    "CNVAnalysis.binSize": 5000,
    "CNVAnalysis.cnvRatiosBed": None,
    "CNVAnalysis.genomeName": "hg19",
    "CNVAnalysis.binSize": 5000,
    "CNVAnalysis.bypassCNVRescalingStep": False,
    "CNVAnalysis.dockerImage": "us.gcr.io/broad-epi-dev/epi-analysis",
    "CNVAnalysis.outFilesDir": "gs://broad-epi-dev-aggregated-alns/",
    "CNVAnalysis.outJsonDir": "gs://broad-epi-dev-cnv-output-jsons/"
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
    'workflowUrl': 'https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/wdls/cnv.wdl',
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
