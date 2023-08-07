# Send request to launch job

require_script 'system_variables'

def submit_jobs(params)
    # Submit the request 
    response = call_external_service(ENDPOINT, nil) do |req, http|
        req['Content-Type'] = "application/json; encoding='utf-8'; odata=verbose"
        req['Accept'] = "application/json"
        req.body = { 'jobs': params }.to_json
    end

    # Display successes and failures for each subject
    submitted = []
    failures = []
    response['jobs'].each do |job|
        status = job['response']['status']
        if status == 'Submitted' or status == 'On Hold'
            submitted.push(job['subj_name'])
        else
            failures.push({
                :status => status,
                :subj_name => job['subj_name']
            })
        end
    end

    submitted_string = submitted.join(', ') || 'None'
    failure_string = failures.length() > 0 ? '<br>' + failures.map{ |f| "<b>#{f[:subj_name]}:</b> #{f[:status]}"}.join('<br>') : 'None'

    show_message("<b>Submitted:</b> #{submitted_string}<br><br><b>Failures: </b>#{failure_string}")
end
