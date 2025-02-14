import io
import os
from datetime import datetime
import json
import requests
import functions_framework
from google.cloud import kms
from google.cloud import storage
import google.auth.transport.requests
from google.oauth2 import service_account
# from format_shareseq_proto_inputs import format_shareseq_proto_inputs
from format_helpers import create_barcode_files
from format_helpers import create_terra_table
from format_helpers import create_terra_table_chip
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


def format_chipseq_import_inputs(project, request, configuration):
    configuration["inputs"] = {
        "BclToFastq.bcl": f'"{request.get("bcl")}"',
        "BclToFastq.candidateMolecularBarcodes": json.dumps(request.get("candidate_molecular_barcodes")),
        "BclToFastq.candidateMolecularIndices": json.dumps(request.get("candidate_molecular_indices")),
        "BclToFastq.readStructure": f'"{request.get("read_structure")}"',
        "BclToFastq.pipelines": json.dumps(request.get("pipelines")),
        "BclToFastq.dockerImage": '"us.gcr.io/{0}/alignment-tools"'.format(project),
        "BclToFastq.outputDir": '"gs://{0}-lane-subsets"'.format(project),
    }

    return configuration


def format_chipseq_inputs(project, request, configuration):
    genome = request.get("genome_name")

    configuration["inputs"] = {
        "ChipSeq.fasta": '"gs://{0}-genomes/{1}/{1}.fasta"'.format(project, genome),
        "ChipSeq.donor": f'"{request.get("donor")}"',
        "ChipSeq.genomeName": f'"{request.get("genome_name")}"',
        "ChipSeq.laneSubsets": json.dumps(request.get("lane_subsets")),
        "ChipSeq.peakStyles": json.dumps(request.get("peak_styles")),
        # "ChipSeq.picard_mark_duplicates_basic.instrumentModel": request.get(
        #     "instrument_model"
        # ),
        "ChipSeq.context": json.dumps(request.get("context")),
        "ChipSeq.dockerImage": '"us.gcr.io/{0}/alignment-tools"'.format(project),
        "ChipSeq.classifierDockerImage": '"us.gcr.io/{0}/classifier"'.format(project),
        "ChipSeq.outputJsonDir": '"gs://{0}-chipseq-output-jsons"'.format(project),
    }

    return configuration


def format_cnv_inputs(project, request, configuration):
    configuration["inputs"] = {
        "CNVAnalysis.bam": f'"{request.get("bam")}"',
        "CNVAnalysis.genomeName": f'"{request.get("genome_name")}"',
        "CNVAnalysis.bypassCNVRescalingStep": f'{request.get("bypass_rescaling")}',
        "CNVAnalysis.context": json.dumps(request.get("context")),
        "CNVAnalysis.dockerImage": '"us.gcr.io/{0}/epi-analysis"'.format(project),
        "CNVAnalysis.outFilesDir": '"gs://{0}-aggregated-alns/"'.format(project),
        "CNVAnalysis.outJsonDir": '"gs://{0}-cnv-output-jsons/"'.format(project),
    }

    cnv_ratios_bed = request.get("cnv_ratios_bed")
    if cnv_ratios_bed is not None:
         configuration["inputs"]["CNVAnalysis.cnvRatiosBed"] = f'"{cnv_ratios_bed}"'

    return configuration


def format_shareseq_import_inputs(project, request, configuration):
    # Create and upload barcode files
    r1 = create_barcode_files(request.get('pipelines')[0].get('round1Barcodes'), project)
    r2 = create_barcode_files(request.get('pipelines')[0].get('round2Barcodes'), project)
    r3 = create_barcode_files(request.get('pipelines')[0].get('round3Barcodes'), project)
    request['pipelines'][0]['round1Barcodes'] = r1
    request['pipelines'][0]['round2Barcodes'] = r2
    request['pipelines'][0]['round3Barcodes'] = r3

    configuration["inputs"] = {
        "SSBclToFastq.bcl": '"{0}/{1}"'.format(
                request.get("bucket"), request.get("bcl")
            ),
        "SSBclToFastq.zipped": f'{request.get("zipped")}',
        "SSBclToFastq.candidateMolecularBarcodes": json.dumps(
            request.get("candidate_molecular_barcodes")
        ),
        "SSBclToFastq.candidateMolecularIndices": json.dumps(
            request.get("candidate_molecular_indices")
        ),
        # "SSBclToFastq.readStructure": request.get("read_structure"),
        # "SSBclToFastq.sequencingCenter": request.get("sequencing_center"),
        "SSBclToFastq.pipelines": json.dumps(request.get("pipelines")),
        "SSBclToFastq.dockerImage": '"mknudson/task_preprocess:update-correction"',
        "SSBclToFastq.outputDir": '"gs://{0}-ss-lane-subsets/"'.format(project),
    }

    return configuration


def format_shareseq_proto_inputs(project, request, configuration):
    tsv = create_terra_table(request, project)

    configuration["inputs"] = {
        "TerraUpsert.tsv": f'"{tsv}"',
        "TerraUpsert.terra_project": f'"{request.get("terra_project")}"',
        "TerraUpsert.workspace_name": f'"{request.get("workspace_name")}"',
    }

    return configuration
    # Terminate the rest of the cloud function execution
    # sys.exit()


def format_chipseq_export_inputs(project, request, configuration):
    tsv = create_terra_table_chip(request, project)

    configuration["inputs"] = {
        "TerraUpsert.tsv": f'"{tsv}"',
        "TerraUpsert.terra_project": f'"{request.get("terra_project")}"',
        "TerraUpsert.workspace_name": f'"{request.get("workspace_name")}"',
    }

    return configuration
    # Terminate the rest of the cloud function execution
    # sys.exit()


formatters = {
    "chip-seq-import": format_chipseq_import_inputs,
    "chip-seq": format_chipseq_inputs,
    "chip-seq-export": format_chipseq_export_inputs,
    "cnv": format_cnv_inputs,
    "share-seq-import": format_shareseq_import_inputs,
    "share-seq-proto": format_shareseq_proto_inputs,
}

wdls = {
    "chip-seq-import": "ChIP-seq-import",
    "chip-seq": "ChIP-seq",
    "chip-seq-export": "terra-upsert",
    "cnv": "CNV",
    "share-seq-import": "SHARE-seq-import",
    "share-seq-proto": "terra-upsert",
}

workflow_parsers = {
    "chip-seq-import": imports.import_bcl_outputs,
    "chip-seq": imports.import_chipseq_outputs,
    "chip-seq-export": imports.import_chipseq_export_outputs,
    "cnv": imports.import_cnv_outputs,
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
        # Update method configuration
        method = wdls[req["workflow"]]
        method_endpoint = (
            "https://api.firecloud.org/api/workspaces/"
            "Shoresh_operations_workflows/lims_terra/"
            f"method_configs/Shoresh_operations_workflows/{method}"
        )
        configuration = requests.get(method_endpoint, headers=header).json()

        # Reset inputs and outputs
        configuration["inputs"] = {}
        configuration["outputs"] = {}
        requests.post(method_endpoint, headers=header, json=configuration)

        inputs = formatters[req["workflow"]](project, req, configuration)
        header["Content-Type"] = "application/json"
        print(f"Method configuration: {json.dumps(inputs, indent=2)}")

        method_response = requests.post(
            method_endpoint,
            headers=header,
            json=inputs
        )
        print(f"Status Code: {method_response.status_code}")
        print(f"Response Text: {json.dumps(method_response.json(), indent=2)}")

        comment = req.get("subj_name")

        # Submit the workflow to cromwell
        submission_manifest = {
            "methodConfigurationNamespace": "Shoresh_operations_workflows",
            "methodConfigurationName": method,
            "userComment": comment[:1000] if len(comment) > 1000 else comment,
            "entityType": None,
            "entityName": None,
            "expression": None,
            "useCallCache": True,
            "deleteIntermediateOutputFiles": False,
            "useReferenceDisks": False,
            "memoryRetryMultiplier": 1,
            "workflowFailureMode": "NoNewCalls",
            "ignoreEmptyOutputs": True
        }

        submission_endpoint = (
            "https://api.firecloud.org/api/workspaces/"
            "Shoresh_operations_workflows/lims_terra/submissions"
        )

        response = requests.post(
            submission_endpoint, json=submission_manifest, headers=header
        )

        print(f"Cromwell tatus Code: {response.status_code}")
        print(f"Cromwell response Text: {json.dumps(response.json(), indent=2)}")

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
