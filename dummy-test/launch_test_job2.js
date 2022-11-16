const FormData = require('form-data');

const wdl_url = 'https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/lims_test.wdl';
const sa_key = ''; /* obtain from keys/ */
const client_email = 'cloudbuild@broad-epi-dev.iam.gserviceaccount.com';

const form = new FormData();
form.append('workflowSource', wdl_url);
form.append('workflowOnHold', 'false');
form.append('collectionName', 'broad-epi-dev-beta2');
form.append('workflowInputs', '{\"helloWorld\":\"hello world, from morgane\"}');
form.append(
    'workflowOptions',
    JSON.stringify({
        backend: 'PAPIv2',
        google_project: 'broad-epi-dev',
        user_service_account_json: sa_key,
        google_compute_service_account: client_email,
        jes_gcs_root: 'gs://broad-epi-dev-cromwell/workflows',
        monitoring_image: 'us.gcr.io/broad-epi-dev/cromwell-task-monitor-bq',
        final_workflow_log_dir: 'gs://broad-epi-dev-cromwell-logs',
        default_runtime_attributes: {
            disks: 'local-disk 10 HDD',
            maxRetries: 1,
            preemptible: 3,
            zones: ['us-east1-b', 'us-east1-c', 'us-east1-d']
        },
    })
);

const xhr = new XMLHttpRequest();

xhr.addEventListener('load', (event) => {
    alert('Yeah! Data sent and response loaded.');
});
xhr.addEventListener('error', (event) => {
    alert('Oops! Something went wrong.');
});

xhr.open('POST', 'https://cromwell.caas-prod.broadinstitute.org/api/workflows/v1p');
xhr.setRequestHeader('authorization', '' /* obtain from launch_test_job.py */)
xhr.send(form);
