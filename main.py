import os
import functions_framework

# import cromwell
# import custom lims api wrapper


@functions_framework.http
def launch_cromwell(request):
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

    print(os.environ.get('KEY', 'Specified environment variable is not set.'))

    return 'Hello World!'
