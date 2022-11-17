import os
import functions_framework
from google.cloud import runtimeconfig

from cromwell_tools import api
from cromwell_tools.cromwell_auth import CromwellAuth


@functions_framework.http
def launch_cromwell(request):
    # Grab Cromwell SA key from the Runtime Config
    # config_name = os.environ.get(
    #     'CONFIG', 'CONFIG environment variable is not set')
    # key_name = os.environ.get('KEY', 'KEY environment variable is not set')

    # client = runtimeconfig.Client()
    # config = client.config(config_name)
    # key = config.get_variable(key_name)

    # # Decrypt key
    # print('encrypted key value')
    # print(key.value)

    key = os.environ.get('KEY', 'KEY environment variable is not set')
    print('encrypted key')
    print(key)

    # Authenticate to Cromwell
    # auth = CromwellAuth.harmonize_credentials(
    #     service_account_key='../keys/lims_cromwell_user_sa_key-dev.json',
    #     url='https://cromwell.caas-prod.broadinstitute.org'
    # )

    # TODO submit job
    # response = api.submit(
    #     auth=auth,
    #     wdl_file='https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/cnv-test/cnv.wdl',
    #     inputs_files=['inputs.json'],
    #     options_file='options.json',
    #     collection_name='broad-epi-dev-beta2'
    # )
    # return response.text

    return 'Hello World!'
