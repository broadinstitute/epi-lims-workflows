import os
import functions_framework
from google.cloud import runtimeconfig

# import cromwell
# import custom lims api wrapper


@functions_framework.http
def launch_cromwell(request):
    config_name = os.environ.get(
        'CONFIG', 'CONFIG environment variable is not set')
    key_name = os.environ.get('KEY', 'KEY environment variable is not set')

    client = runtimeconfig.Client()
    print('got client')
    config = client.config(config_name)
    print('got config')
    key = config.get_variable(key_name)
    print('encrypted key:', key)

    # TODO fetch SA key either from fn env variable or runtime config
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
