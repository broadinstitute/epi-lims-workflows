import io
import os
import json
import functions_framework
from google.cloud import kms

from cromwell_tools import api
from cromwell_tools.cromwell_auth import CromwellAuth


def get_runtime_options(project):
    return io.BytesIO({
        "backend": "PAPIv2",
        "google_project": project,
        "jes_gcs_root": "gs://{0}-cromwell/workflows".format(project),
        "monitoring_image": "us.gcr.io/{0}/cromwell-task-monitor-bq".format(project),
        "final_workflow_log_dir": "gs://{0}-cromwell-logs".format(project),
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
    }.encode())


def get_wdl(name):
    return {
        'cnv': 'https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/cnv-test/cnv.wdl'
    }[name]


@functions_framework.http
def launch_cromwell(request):
    # Grab KMS key information and encrypted Cromwell SA credentials
    # from environment variables passed in via cloudbuild
    encrypted_key = os.environ.get(
        'KEY', 'KEY environment variable is not set')
    project = os.environ.get(
        'PROJECT', 'PROJECT environment variable is not set')
    endpoint = os.environ.get(
        'ENDPOINT', 'ENDPOINT environment variable is not set')
    kms_key = os.environ.get(
        'KMS_KEY', 'KMS_KEY environment variable is not set')
    kms_location = os.environ.get(
        'KMS_LOCATION', 'KMS_LOCATION environment variable is not set')

    # Decrypt the Cromwell SA credentials
    client = kms.KeyManagementServiceClient()
    key_name = client.crypto_key_path(
        project, kms_location, kms_key, kms_key)
    decrypt_response = client.decrypt(
        request={'name': key_name, 'ciphertext': encrypted_key})

    key_json = json.loads(decrypt_response.plaintext)

    # Authenticate to Cromwell
    auth = CromwellAuth.harmonize_credentials(
        service_account_key=key_json,
        url=endpoint
    )

    options = get_runtime_options(project)
    inputs = io.BytesIO({
        "CNVAnalysis.bam": "gs://broad-epi-dev-aggregated-alns/aggregated_aln_028227.bam",
        "CNVAnalysis.binSize": 5000,
        "CNVAnalysis.cnvRatiosBed": None,
        "CNVAnalysis.genomeName": "hg19",
        "CNVAnalysis.binSize": 5000,
        "CNVAnalysis.bypassCNVRescalingStep": False,
        "CNVAnalysis.dockerImage": "us.gcr.io/broad-epi-dev/epi-analysis",
        "CNVAnalysis.outFilesDir": "gs://broad-epi-dev-aggregated-alns/",
        "CNVAnalysis.outJsonDir": "gs://broad-epi-dev-cnv-output-jsons/"
    }.encode())

    # Submit job
    response = api.submit(
        auth=auth,
        wdl_file='https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/cnv-test/cnv.wdl',
        inputs_files=[inputs],
        options_file=options,
        collection_name='broad-epi-dev-beta2'
    )

    return response.text
