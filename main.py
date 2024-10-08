import io
import os
import csv
from datetime import datetime
import subprocess
import json
import requests
import functions_framework
from google.cloud import kms
from google.cloud import storage
import google.auth.transport.requests
from google.oauth2 import service_account
# from format_shareseq_proto_inputs import format_shareseq_proto_inputs
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


def create_barcode_files(barcodes):
    filenames = []
    dir = '/tmp'
    # Upload the CSV file to Google Cloud Storage
    storage_client = storage.Client()
    bucket_name = "broad-epi-cromwell"
    bucket = storage_client.bucket(bucket_name)
    for barcode_set in barcodes:
        # Use the first entry of the first sublist as the filename
        basename = barcode_set[0][0]
        filename = f'{dir}/{basename}.tsv'
        blob = bucket.blob(basename)
        if blob.exists():
            print(f'{basename} already exists in {bucket_name}. Skipping upload.')
        else:
            # Create the TSV file locally
            with open(filename, 'w', newline='') as file:
                writer = csv.writer(file, delimiter='\t')
                for row in barcode_set:
                    writer.writerow(row)
            # Upload the file to GCS
            blob.upload_from_filename(filename)
            print(f'{filename} has been uploaded to {bucket_name}.')
        # Get the GCS path and append to the list
        gcs_path = f'gs://{bucket_name}/{basename}'
        filenames.append(gcs_path)
    return filenames


def format_shareseq_import_inputs(project, request):
    # Create and upload barcode files
    request['pipelines'][0]['round1Barcodes'] = create_barcode_files(request.get('pipelines')[0].get('round1Barcodes'))
    request['pipelines'][0]['round2Barcodes'] = create_barcode_files(request.get('pipelines')[0].get('round2Barcodes'))
    request['pipelines'][0]['round3Barcodes'] = create_barcode_files(request.get('pipelines')[0].get('round3Barcodes'))
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
            "SSBclToFastq.dockerImage": "mknudson/task_preprocess:update-correction",
            "SSBclToFastq.outputDir": "gs://{0}-ss-lane-subsets/".format(project),
        }
    )

def format_shareseq_proto_inputs(project, request):
    dir = '/tmp'
    tsv_file = '{}/output.tsv'.format(dir)
    
    # Open the file in write mode
    with open(tsv_file, 'w', newline='') as file:
        # Create a TSV writer
        writer = csv.writer(file,  delimiter='\t', quotechar='"', escapechar = '\\', quoting=csv.QUOTE_NONE)
        
        data = request.get('lane_subsets')
        
        # Create path to whitelists
        bucket = 'gs://broad-epi-ss-lane-subsets/'
        suffix = '_whitelist.txt'
        whitelists = ["{}{}{}".format(bucket, s, suffix) for s in data['ssCopas']]
        
        n_rows = len(data['libraries'])
        
        # Header
        writer.writerow(['Library','PKR','R1_subset','Type','Whitelist','Raw_FASTQ_R1','Raw_FASTQ_R2','Genome','Notes', 'Context'])
        
        # Create metadata JSONs
        contexts = []
        for name, uid in zip(request['subj_name'].split(','), request['subj_id'].split(',')):
            contexts.append(json.dumps({'name': name, 'uid': uid }))
            
        for row_values in zip(data['libraries'], data['pkrIds'], data['round1Subsets'], data['sampleTypes'], whitelists, data['reads1'], data['reads2'], data['genomes'], ['']*n_rows, contexts):
            writer.writerow(row_values)
    
    script_path = 'write_terra_tables.py'
    
    # time = datetime.now()
    # table_name = time.strftime("%y-%m-%d_%H%M_proto")
    table_name = request.get('table_name')
    command = ['python', script_path, '--input', tsv_file, '--name', table_name, '--dir', dir]
    if request.get('group'):
        command.append('--group' )
    subprocess.run(command)
    
    # Upload the CSV file to Google Cloud Storage
    storage_client = storage.Client()
    bucket_name = "broad-epi-cromwell"
    blob_name = "{}_run.tsv".format(table_name)
    
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(blob_name)
    blob.upload_from_filename("{}/run.tsv".format(dir))
    
    return dict_to_bytes_io(
        {
            "TerraUpsert.tsv": 'gs://{}/{}'.format(bucket_name, blob_name),
            "TerraUpsert.terra_project": request.get("terra_project"),
            "TerraUpsert.workspace_name": request.get("workspace_name"),
        }
	)
	# Terminate the rest of the cloud function execution
    # sys.exit()

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
    "share-seq-proto": "https://raw.githubusercontent.com/broadinstitute/epi-lims-workflows/release/wdls/terra_upsert.wdl",
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
