import json
from google.cloud import storage

storage_client = storage.Client()
bucket = storage_client.get_bucket('broad-epi-dev-morgane-test')

blob = bucket.blob('chipseq_outputs.json')
blob = blob.download_as_string()
blob = blob.decode('utf-8')

data = json.loads(blob)

print(data)
