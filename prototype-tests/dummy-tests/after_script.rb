bam = subj['BAM Filename URI']

params[:javascript] = <<-EOS
  const wdl_url = 'https://raw.githubusercontent.com/broadinstitute/epi-lims-wdl-test/main/cnv-test/cnv.wdl';
  const sa_key = '';
  const client_email = 'lims-cromwell-user@broad-epi-dev.iam.gserviceaccount.com';

  const form = new FormData();
  form.append('collectionName', 'broad-epi-dev-beta2');
  form.append('workflowUrl', wdl_url);
  form.append('workflowInputs', JSON.stringify({
    "CNVAnalysis.bam": `#{bam}`,
    "CNVAnalysis.bypassCNVRescalingStep": false,
    "CNVAnalysis.dockerImage": 'us.gcr.io/broad-epi-dev/epi-analysis',
    "CNVAnalysis.outFilesDir": 'gs://broad-epi-dev-aggregated-alns/',
    "CNVAnalysis.outJsonDir": 'gs://broad-epi-dev-cnv-output-jsons/'
  }));
  form.append(
      'workflowOptions',
      JSON.stringify({
          backend: 'PAPIv2',
          google_project: 'broad-epi-dev',
          user_service_account_json: sa_key,
          google_compute_service_account: client_email,
          jes_gcs_root: 'gs://broad-epi-dev-cromwell/workflows',
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
  xhr.setRequestHeader('authorization', 'Bearer XXXX')
  xhr.send(form);
EOS
