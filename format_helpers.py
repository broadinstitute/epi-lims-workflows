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