const fs = require('fs');
const axios = require('axios');
const FormData = require('form-data');
const stringify = require('json-stable-stringify');

const wdl_url = 'https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/lims_test.wdl';
const sa_key = JSON.parse(fs.readFileSync('keys/cloudbuild_sa_key-dev.json'));
const client_email = sa_key['client_email'];

const form = new FormData();
form.append('collectionName', 'broad-epi-dev-beta2');
form.append('workflowSource', wdl_url);
form.append('workflowInputs', stringify({
    helloWorld: 'hello world from morgane'
}));
form.append(
    'workflowOptions',
    stringify({
        backend: 'PAPIv2',
        google_project: 'broad-epi-dev',
        user_service_account_json: stringify(sa_key),
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
form.append('workflowOnHold', 'false');

const api = axios.create({
    baseURL: "https://cromwell.caas-prod.broadinstitute.org/api/workflows/v1"
});
api.post('', form, {
    headers: { 'authorization': '' /* obtain from launch_test_job.py */ }
}).then(resp => {
    console.log(resp.data);
}).catch(err => {
    console.log(err);
})
