import io
import os
import json
import requests
import functions_framework
from google.cloud import kms
from google.cloud import storage
import google.auth.transport.requests
from google.oauth2 import service_account
from format_shareseq_proto_inputs import format_shareseq_proto_inputs
import imports

# from transfer import submit_bcl_transfer


def dict_to_bytes_io(d):
    return io.BytesIO(json.dumps(d).encode())


def download_gcs_file(bucket, name):
    storage_client = storage.Client()
    bucket = storage_client.get_bucket(bucket)
    blob = bucket.blob(name)
    blob = blob.download_as_string()
    blob = blob.decode("utf-8")
    return json.loads(blob)


def get_runtime_options(project, sa_key):
    return dict_to_bytes_io(
        {
            "backend": "PAPIv2",
            "google_project": project,
            "jes_gcs_root": "gs://{0}-cromwell/workflows".format(project),
            # "monitoring_image": "us.gcr.io/{0}/cromwell-task-monitor-bq".format(project),
            "final_workflow_log_dir": "gs://{0}-cromwell-logs".format(project),
            "google_compute_service_account": sa_key["client_email"],
            "user_service_account_json": json.dumps(sa_key),
            "default_runtime_attributes": {
                "disks": "local-disk 10 HDD",
                "maxRetries": 1,
                "preemptible": 3,
                "zones": ["us-east1-b", "us-east1-c", "us-east1-d"],
            },
        }
    )


# TODO these formatters are a little redundant - we could simply pass
# cnvRatiosBed directly in camel case and do something a little more clever


def format_cnv_inputs(project, request):
    return dict_to_bytes_io(
        {
            "CNVAnalysis.bam": request.get("bam"),
            "CNVAnalysis.binSize": 5000,
            "CNVAnalysis.cnvRatiosBed": request.get("cnv_ratios_bed"),
            "CNVAnalysis.genomeName": request.get("genome_name"),
            "CNVAnalysis.bypassCNVRescalingStep": request.get("bypass_rescaling"),
            "CNVAnalysis.dockerImage": "us.gcr.io/{0}/epi-analysis".format(project),
            "CNVAnalysis.outFilesDir": "gs://{0}-aggregated-alns/".format(project),
            "CNVAnalysis.outJsonDir": "gs://{0}-cnv-output-jsons/".format(project),
        }
    )


def format_import_inputs(project, request):
    return dict_to_bytes_io(
        {
            "BclToFastq.bcl": request.get("bcl"),
            "BclToFastq.candidateMolecularBarcodes": request.get(
                "candidate_molecular_barcodes"
            ),
            "BclToFastq.candidateMolecularIndices": request.get(
                "candidate_molecular_indices"
            ),
            "BclToFastq.readStructure": request.get("read_structure"),
            "BclToFastq.sequencingCenter": request.get("sequencing_center"),
            "BclToFastq.dockerImage": "us.gcr.io/{0}/alignment-tools".format(project),
            "BclToFastq.outputDir": "gs://{0}-lane-subsets/".format(project),
        }
    )


def format_shareseq_import_inputs(project, request):
    return dict_to_bytes_io(
        {
            "SSBclToFastq.bcl": "{0}/{1}".format(
                request.get("bucket"), request.get("bcl")
            ),
            "SSBclToFastq.zipped": request.get("zipped"),
            "SSBclToFastq.candidateMolecularBarcodes": request.get(
                "candidate_molecular_barcodes"
            ),
            "SSBclToFastq.candidateMolecularIndices": request.get(
                "candidate_molecular_indices"
            ),
            # "SSBclToFastq.readStructure": request.get("read_structure"),
            # "SSBclToFastq.sequencingCenter": request.get("sequencing_center"),
            "SSBclToFastq.pipelines": request.get("pipelines"),
            "SSBclToFastq.dockerImage": "mknudson/preprocess:demux-qc-fix",
            "SSBclToFastq.outputDir": "gs://{0}-ss-lane-subsets/".format(project),
        }
    )


def format_chipseq_inputs(project, request):
    genome = request.get("genome_name")
    return dict_to_bytes_io(
        {
            "ChipSeq.fasta": "gs://{0}-genomes/{1}/{1}.fasta".format(project, genome),
            "ChipSeq.donor": request.get("donor"),
            "ChipSeq.genomeName": request.get("genome_name"),
            "ChipSeq.laneSubsets": request.get("lane_subsets"),
            "ChipSeq.peakStyles": request.get("peak_styles"),
            "ChipSeq.picard_mark_duplicates_basic.instrumentModel": request.get(
                "instrument_model"
            ),
            "ChipSeq.dockerImage": "us.gcr.io/{0}/alignment-tools".format(project),
            "ChipSeq.classifierDockerImage": "us.gcr.io/{0}/classifier".format(project),
            "ChipSeq.outputJsonDir": "gs://{0}-chipseq-output-jsons".format(project),
        }
    )


wdls = {
    "cnv": "https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/wdls/cnv.wdl",
    "import": "https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/wdls/imports.wdl",
    "chipseq": "https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/wdls/chipseq.wdl",
    "share-seq-import": "https://raw.githubusercontent.com/broadinstitute/epi-lims-workflows/release/wdls/shareseq_imports.wdl",
}

formatters = {
    "cnv": format_cnv_inputs,
    "import": format_import_inputs,
    "chipseq": format_chipseq_inputs,
    "share-seq-import": format_shareseq_import_inputs,
    "share-seq-proto": format_shareseq_proto_inputs,
}

workflow_parsers = {
    "cnv": imports.import_cnv_outputs,
    "import": imports.import_bcl_outputs,
    "chipseq": imports.import_chipseq_outputs,
    "share-seq-import": imports.import_shareseq_import_outputs,
    "share-seq-proto": imports.import_shareseq_proto_outputs,
}


@functions_framework.http
def launch_cromwell(request):
    request_json = request.get_json(silent=True)

    # Grab KMS key information and encrypted Cromwell SA credentials
    # from environment variables passed in via cloudbuild
    encrypted_key = os.environ.get("KEY")
    project = os.environ.get("PROJECT")
    endpoint = os.environ.get("ENDPOINT")
    kms_key = os.environ.get("KMS_KEY")
    kms_location = os.environ.get("KMS_LOCATION")

    # Decrypt the Cromwell SA credentials
    client = kms.KeyManagementServiceClient()
    key_name = client.crypto_key_path(project, kms_location, kms_key, kms_key)
    decrypt_response = client.decrypt(
        request={"name": key_name, "ciphertext": encrypted_key}
    )

    sa_key = json.loads(decrypt_response.plaintext)

    # Get authorization header for Cromwell SA
    credentials = service_account.Credentials.from_service_account_info(
        sa_key, scopes=["email", "openid", "profile"]
    )
    if not credentials.valid:
        credentials.refresh(google.auth.transport.requests.Request())
    header = {}
    credentials.apply(header)

    # Get Cromwell runtime options
    options = get_runtime_options(project, sa_key)

    # Submit jobs
    responses = []
    for req in request_json["jobs"]:
        # Submit the workflow to cromwell
        inputs = formatters[req["workflow"]](project, req)
        submission_manifest = {
            "workflowUrl": wdls[req["workflow"]],
            "workflowInputs": inputs,
            "collectionName": "{0}-beta2".format(project),
            "workflowOnHold": req.get("on_hold", False),
            "workflowOptions": options,
        }

        request_size = len(inputs.getvalue())
        print("Request Size:", request_size, "bytes")

        response = requests.post(
            endpoint, data=submission_manifest, auth=None, headers=header
        )
        print("Request Headers:", response.request.headers)
        print("Response Headers:", response.headers)

        print("cromwell response:", response.status_code)
        print("cromwell response:", response.text)
        responses.append({"subj_name": req["subj_name"], "response": response.json()})
        # Start the bcl transfer for import workflows
        # if req['workflow'] == 'import':
        #     submit_bcl_transfer(
        #         project, req['bcl'], response.json()['id'], key_json)

    return {"jobs": responses}


@functions_framework.cloud_event
def on_workflow_done(cloud_event):
    print("on_workflow_done triggered")

    # Grab lims user/password from secret
    username = os.environ.get("LIMS_USERNAME")
    password = os.environ.get("LIMS_PASSWORD")
    project = os.environ.get("PROJECT")

    print("downloading file")

    # Download Cromwell job outputs from GCS
    outputs = download_gcs_file(cloud_event.data["bucket"], cloud_event.data["name"])

    # Parse Cromwell job outputs and write to LIMS
    workflow = outputs["workflowType"]
    print(f"Workflow completion: {workflow}")
    workflow_parsers[workflow](project, username, password, outputs)

    # TODO launch any other jobs that need to run
    # subsequently

    # TODO return response
