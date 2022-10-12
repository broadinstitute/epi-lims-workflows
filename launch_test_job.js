const axios = require('axios');
const FormData = require('form-data');
const stringify = require('json-stable-stringify');

const wdl_url = 'https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/lims_test.wdl';

const form = new FormData();
form.append('collectionName', 'caas-prod');
form.append('workflowSource', wdl_url);
form.append('workflowInputs', stringify({
    helloWorld: 'hello world from morgane'
}));
form.append(
    'workflowOptions',
    stringify({
        backend: 'PAPIv2',
        google_project: 'broad-epi',
        user_service_account_json: stringify(
            { /* SA key json */ }
        ),
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
// form.append(
//     'labels',
//     stringify({
//         ...labels,
//         'workflow-version': getFunctionsRuntime().version,
//     })
// );
// form.append('workflowOnHold', hold ? 'true' : 'false');

const api = axios.create({
    baseURL: "https://cromwell.caas-prod.broadinstitute.org/api/workflows/v1"
});
api.post('', form, {
    headers: form.getHeaders()
}).catch(err => {
    console.log(err);
})
