require 'json'
require 'uri'
require 'net/http'

endpoint = 'https://cromwell.caas-prod.broadinstitute.org/api/workflows/v1'

sa_key = JSON.parse(File.read('keys/cloudbuild_sa_key-dev.json'))
client_email = sa_key['client_email']

workflow_source = 'https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/lims_test.wdl'

workflow_inputs = JSON.generate({
    "helloWorld": "hello world, from morgane"
}).encode('utf-8')

puts workflow_inputs

workflow_options = {
    "backend": "PAPIv2",
    "google_project": "broad-epi-dev",
    "jes_gcs_root": "gs://broad-epi-dev-cromwell/workflows",
    "monitoring_image": "us.gcr.io/broad-epi-dev/cromwell-task-monitor-bq",
    "final_workflow_log_dir": "gs://broad-epi-dev-cromwell-logs",
    "user_service_account_json": JSON.generate(sa_key),
    "google_compute_service_account": client_email,
    "default_runtime_attributes": {
        "disks": "local-disk 10 HDD",
        "maxRetries": 1,
        "preemptible": 3,
        "zones": [
            "us-east1-b",
            "us-east1-c",
            "us-east1-d"
        ]
    }
}

submission_manifest = {
	'workflowSource' => workflow_source,
	'workflowInputs' => workflow_inputs,
	'collectionName' => 'broad-epi-dev-beta2',
	'workflowOptions' => workflow_options,
    'workflowOnHold' => false
}

uri = URI(endpoint)
res = Net::HTTP.post_form(
    uri,
    'data' => submission_manifest,
    'auth' => nil,
    # obtain from launch_test_job.py
    'headers' => {'authorization': ''}
)
puts res.body
