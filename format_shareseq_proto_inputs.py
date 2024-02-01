import csv
import subprocess
from google.cloud import storage
import sys
from datetime import datetime

# # Open the JSON file for reading
# with open('test.json', 'r') as json_file:
#     req = json.load(json_file)

def format_shareseq_proto_inputs(project, request):
    dir = '/tmp'
    tsv_file = '{}/output.tsv'.format(dir)
    
    # Open the file in write mode
    with open(tsv_file, 'w', newline='') as file:
        # Create a TSV writer
        writer = csv.writer(file, delimiter='\t')
        
        data = request.get('lane_subsets')
        
        # Create path to whitelists
        bucket = 'gs://broad-epi-ss-lane-subsets/'
        suffix = '_whitelist.txt'
        whitelists = ["{}{}{}".format(bucket, s, suffix) for s in data['ssCopas']]
        
        n_rows = len(data['libraries'])
        
        # Header
        writer.writerow(['Library','PKR','R1_subset','Type','Whitelist','Raw_FASTQ_R1','Raw_FASTQ_R2','Genome','Notes'])
        
        for row_values in zip(data['libraries'], data['pkrIds'], data['round1Subsets'], data['sampleTypes'], whitelists, data['reads1'], data['reads2'], data['genomes'], ['']*n_rows):
            writer.writerow(row_values)
    
    script_path = 'write_terra_tables.py'
    
    time = datetime.now()
    table_name = time.strftime("%y-%m-%d_%H%M_proto")
    subprocess.run(['python', script_path, '--input', tsv_file, '--name', table_name, '--dir', dir])
    
    # Upload the CSV file to Google Cloud Storage
    storage_client = storage.Client()
    bucket_name = "broad-epi-cromwell"
    blob_name = "{}_run.tsv".format(table_name)
    
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(blob_name)
    blob.upload_from_filename("{}/run.tsv".format(dir))
    
	# Terminate the rest of the cloud function execution
    sys.exit()