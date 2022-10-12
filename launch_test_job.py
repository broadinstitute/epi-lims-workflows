import time
from cromwell_tools import api
from cromwell_tools.cromwell_auth import CromwellAuth

# Authenticate
auth = CromwellAuth.harmonize_credentials(
    service_account_key='keys/lims_cromwell_user_sa_key-dev.json',
    url='https://cromwell.caas-prod.broadinstitute.org'
)

# Submit job
response = api.submit(
    auth=auth, 
    wdl_file='lims_test.wdl', 
    inputs_files=['hello_inputs.json'],
    options_file='hello_options.json',
    collection_name='broad-epi-dev-beta2' # this causes Access Denied
    #dependencies
    #label_file
)
print(response.text)

print('Checking job status...')
time.sleep(4)

# Check job status
response = api.status(
    auth=auth, 
    uuid=response.json()['id']
)
print(response.json())