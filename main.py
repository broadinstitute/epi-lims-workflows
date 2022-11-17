import io
import os
import json
import functions_framework
from google.cloud import kms

from cromwell_tools import api
from cromwell_tools.cromwell_auth import CromwellAuth


def dict_to_bytes_io(d):
    return io.BytesIO(json.dumps(d).encode())


def get_runtime_options(project):
    return dict_to_bytes_io({
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
    })


def format_cnv_inputs(project, request):
    return dict_to_bytes_io({
        "CNVAnalysis.bam": request.get('bam'),
        "CNVAnalysis.binSize": 5000,
        "CNVAnalysis.cnvRatiosBed": request.get('cnv_ratios_bed'),
        "CNVAnalysis.genomeName": request.get('genome_name'),
        "CNVAnalysis.bypassCNVRescalingStep": request.get('bypass_rescaling'),
        "CNVAnalysis.dockerImage": "us.gcr.io/{0}/epi-analysis".format(project),
        "CNVAnalysis.outFilesDir": "gs://{0}-aggregated-alns/".format(project),
        "CNVAnalysis.outJsonDir": "gs://{0}-cnv-output-jsons/".format(project)
    })


def get_wdl(name):
    return {
        'cnv': 'https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/cnv-test/cnv.wdl'
    }[name]


formatters = {
    'cnv': format_cnv_inputs
}


@functions_framework.http
def launch_cromwell(request):
    # TODO authentication
    # TODO validate request
    # TODO batch processing (auth, env, kms, cromwell auth)

    request_json = request.get_json(silent=True)
    request_args = request.args

    print('args / json')
    print(request_json)
    print(request_args)

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
    inputs = formatters[request_json['workflow']](project, request_json)

    # Submit job
    response = api.submit(
        auth=auth,
        wdl_file='https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/cnv-test/cnv.wdl',
        inputs_files=[inputs],
        options_file=options,
        collection_name='broad-epi-dev-beta2'
    )

    return response.text
