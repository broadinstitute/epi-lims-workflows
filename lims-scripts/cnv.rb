# After Script of the cnv prototype tool

extend UI
require 'set'

def wce_sort_fn(a, b)
    a['updated_at'] == b['updated_at'] ? a['id'] - b['id'] : (a['updated_at'] <= b['updated_at'] ? -1 : 1)
end

def get_app_wce(alignment)
    app = alignment['Aligment Post Processing']
    if app
        return {
            'biosam' => app['BioSam'],
            'id' => app.id,
            'name' => app.name,
            'updated_at' => app.updated_at,
            'cnv_ratios_bed' => app['CNV Ratios BED URI']
        }
    return {}

# Each subject is an APP
subjects.each do |app|
    ref_seq = app['Reference Sequence']
    biosams = app['Alignments'].map{ |a| a['BioSam'] }.to_set.to_a

    if app['BAM Filename URI'] == nil
        params[:tool_message] = "BAM Filename URI is missing for #{app.name}"
        return
    end
    if ref_seq == nil
        params[:tool_message] = "Reference Sequence is missing for #{app.name}"
        return
    end
    if biosams.length != 1
        params[:tool_message] = "Alignments for #{app.name} must come from exactly 1 BioSam"
        return
    end

    biosam = biosams[0]

    # Get most recent WCE 
    alignments = find_subjects(query:search_query(from:'Alignment') { |a|
        qb.and(
            qb.compare('BioSam', :eq, b),
            qb.compare('Epitopes', :eq, 'WCE'),
            qb.compare('Reference Sequence', :eq, ref_seq)
        )
    })
    wces = alignments.map{ |a| get_app_wce(a) }
    sorted_wces = wces.sort! { |wce1, wce2| wce_sort_fn(wce1, wce2) }
    most_recent_wce = sorted_wces.length ? sorted_wces.pop() : nil

    # Define the input control. If CNV rescaling step isn't bypassed,
    # it's either the Input Control Override specified in lims or the
    # most recent WCE APP associated with this APP's BioSam
    input_control = nil
    cnv_ratios_bed = nil

    wce_override = s['Input Control Override']
    bypass_rescaling = wce_override == 'bypass CNV rescaling step'

    if bypass_rescaling
        input_control = wce_override
    else
        wce = wce_override ? find_subject({
            subject_type: 'Alignment Post Processing',
            name: wce_override
        }) : most_recent_wce

        if !wce
            if wce_override
                params[:tool_message] = "Input Control Override for #{app.name} doesn't exist: #{wce_override}"
                return
            end
            params[:tool_message] = "#{biosam} doesn't have any WCE(s), and no Input Control Override was set for #{app.name}"
            return
        end
        
        is_input_control = app.name == wce.name
        if !is_input_control
            if !wce['cnv_ratios_bed']
                params[:tool_message] = "#{app.name} depends on WCE #{wce.name}, which is missing a CNV Ratios BED URI"
                return
            end
            cnv_ratios_bed = wce['cnv_ratios_bed']
        end

        input_control = wce.name
    end

    # Send request to launch job
    url = "https://cromwell-launcher-hxpirayhja-ue.a.run.app"
    params {
        :app_name => app.name,
        :app_id => app.id,
        :cnv_ratios_bed => cnv_ratios_bed,
        :genome_name => ref_seq.gsub('_picard', ''),
        :bypass_rescaling => bypass_rescaling,
        :input_control => input_control
    }
    intsearch = call_external_service(url, nil) do |req, http|
        req['Content-Type'] = "application/json; encoding='utf-8'; odata=verbose"
        req['Accept'] = "application/json"
        req.body = params.to_json
    end
end

