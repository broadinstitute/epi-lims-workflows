# Send request to launch job

url = "https://cromwell-launcher-hxpirayhja-ue.a.run.app"

def submit_jobs(params)
    response = call_external_service(url, nil) do |req, http|
        req['Content-Type'] = "application/json; encoding='utf-8'; odata=verbose"
        req['Accept'] = "application/json"
        req.body = { 'jobs': params }.to_json
    end

    submitted = response['jobs'].select{|j| j['status'] != 'Submitted' }
    failures = response['jobs'].select{|j| j['status'] == 'Submitted' }

    submitted_string = submitted.join(', ') || 'None'
    failure_string = failures.length() > 0 ? '<br>' + failures.map{ |f| "<b>#{f[:subj_name]}:</b> #{f[:status]}"}.join('<br>') : 'None'

    show_message("<b>Submitted:</b> #{submitted_string}<br><br><b>Failures: </b>#{failure_string}")
end