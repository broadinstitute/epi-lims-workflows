import csv
from google.cloud import storage
import json
import subprocess


def create_barcode_files(barcodes, project):
    filenames = []
    dir = '/tmp'
    # Upload the CSV file to Google Cloud Storage
    storage_client = storage.Client()
    bucket_name = "{0}-cromwell".format(project)
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

def create_terra_table(request, project):
    dir = '/tmp'
    tsv_file = '{}/output.tsv'.format(dir)

    # Open the file in write mode
    with open(tsv_file, 'w', newline='') as file:
        # Create a TSV writer
        writer = csv.writer(file,  delimiter='\t', quotechar='"', escapechar = '\\', quoting=csv.QUOTE_NONE)

        data = request.get('lane_subsets')

        # Create path to whitelists
        bucket = 'gs://{0}-ss-lane-subsets/'.format(project)
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
    bucket_name = "{0}-cromwell".format(project)
    blob_name = "{}_run.tsv".format(table_name)

    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(blob_name)
    blob.upload_from_filename("{}/run.tsv".format(dir))

    return f'gs://{bucket_name}/{blob_name}'

def create_terra_table_chip(request, project):
    dir = '/tmp'
    tsv_file = '{}/output.tsv'.format(dir)
    table_name = request.get('table_name')

    with open(tsv_file, "w", newline="") as file:
        writer = csv.writer(file, delimiter="\t")
        pcs = request["pool_components"]

        # Prepare the header
        header = [
            "entity:{}_id".format(table_name),
            "epitope",
            "celltype",
            "description",
            "rep1-r1-fq",
            "rep1-r2-fq",
        ]

        # Determine the maximum number of control columns dynamically
        max_ctrl = max(
            max(len(row["ctrl_r1"]), len(row["ctrl_r2"])) for row in pcs
        )

        for i in range(1, max_ctrl + 1):
            header.append(f"ctrl{i}-r1-fq")
            header.append(f"ctrl{i}-r2-fq")

        # Write the header to the TSV
        writer.writerow(header)

        # Write each row of data to the TSV
        for row_data in pcs:
            row = [
                row_data["libraries"],  # entity:dna_lib_id
                row_data["epitopes"],   # epitope
                row_data["celltypes"],
                "_".join([row_data["libraries"], row_data["epitopes"], row_data["celltypes"]]),
                json.dumps(row_data["reads1"]),  # rep1-r1-fq
                json.dumps(row_data["reads2"]),  # rep1-r2-fq
            ]
            # Add control data dynamically
            for i in range(max_ctrl):
                ctrl_r1 = (
                    json.dumps(row_data["ctrl_r1"][i])
                    if i < len(row_data["ctrl_r1"])
                    else ""
                )
                ctrl_r2 = (
                    json.dumps(row_data["ctrl_r2"][i])
                    if i < len(row_data["ctrl_r2"])
                    else ""
                )
                row.append(ctrl_r1)
                row.append(ctrl_r2)
            writer.writerow(row)

    # Upload the CSV file to Google Cloud Storage
    storage_client = storage.Client()
    bucket_name = "{0}-cromwell".format(project)
    blob_name = "{}.tsv".format(table_name)

    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(blob_name)
    blob.upload_from_filename(tsv_file)

    return f'gs://{bucket_name}/{blob_name}'