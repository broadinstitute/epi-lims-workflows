import time
from cromwell_tools import api
from cromwell_tools.cromwell_auth import CromwellAuth

# Authenticate
auth = CromwellAuth.harmonize_credentials(
    service_account_key='../keys/cloudbuild_sa_key-dev.json',
    url='https://cromwell.caas-prod.broadinstitute.org'
)
print(auth.header)

# Submit job
response = api.submit(
    auth=auth, 
    wdl_file='cnv.wdl',
    #wdl_file='https://raw.githubusercontent.com/broadinstitute/epi-lims-firebase/master/api/src/workflows/cnv/CNVAnalysis.wdl?token=GHSAT0AAAAAABXPLLE5R3ONZ3DSFSN3VECGY3FMM3Q',
    inputs_files=['inputs.json'],
    options_file='options.json',
    collection_name='broad-epi-dev-beta2'
)
print(response.text)

print('Checking job status...')
time.sleep(4)
response = api.status(
    auth=auth, 
    uuid=response.json()['id']
)
print(response.json())