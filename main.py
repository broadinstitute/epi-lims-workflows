import os
import json
import functions_framework
from google.cloud import kms

from cromwell_tools import api
from cromwell_tools.cromwell_auth import CromwellAuth


@functions_framework.http
def launch_cromwell(request):
    # Grab KMS key information and encrypted Cromwell SA credentials
    # from environment variables passed in via cloudbuild
    encrypted_key = os.environ.get(
        'KEY', 'KEY environment variable is not set')
    project = os.environ.get(
        'PROJECT', 'PROJECT environment variable is not set')
    kms_key = os.environ.get(
        'KMS_KEY', 'KMS_KEY environment variable is not set')
    kms_location = os.environ.get(
        'KMS_LOCATION', 'KMS_LOCATION environment variable is not set')

    # Decrypt the Cromwell SA credentials
    client = kms.KeyManagementServiceClient()
    key_name = client.crypto_key_path(
        project, kms_location, kms_key, kms_key)
    decrypt_response = client.decrypt(
        request={'name': key_name, 'ciphertext': encrypted_key})

    print(json.loads(decrypt_response.plaintext))

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
