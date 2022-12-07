import time
from cromwell_tools import api
from cromwell_tools.cromwell_auth import CromwellAuth

# Authenticate
auth = CromwellAuth.harmonize_credentials(
    service_account_key='../keys/cromwell_user_sa_key-dev.json',
    url='https://cromwell.caas-prod.broadinstitute.org'
)

# Submit job
response = api.submit(
    auth=auth,
    # wdl_file='cnv.wdl',
    wdl_file='https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/cnv-test/cnv.wdl',
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
