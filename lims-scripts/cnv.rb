# After Script of the cnv prototype tool

extend UI
require 'set'

def wce_sort_fn(a, b)
    a.updated_at == b.updated_at ? a.id - b.id : (a.updated_at <= b.updated_at ? -1 : 1)
end

# Each subject is an APP
subjects.each do |s|
    ref_seq = s['Reference Sequence']
    biosams = s['Alignments'].map{ |a| a['BioSam'] }.to_set.to_a

    if s['BAM Filename URI'] == nil
        params[:tool_message] = "BAM Filename URI is missing for #{s.name}"
        return
    end
    if ref_seq == nil
        params[:tool_message] = "Reference Sequence is missing for #{s.name}"
        return
    end
    if biosams.length != 1
        params[:tool_message] = "Alignments for #{s.name} must come from exactly 1 BioSam"
        return
    end

    biosam = biosams[0]

    # Get most recent WCE 
    wces = find_subjects(query:search_query(from:'Alignment') { |a|
        qb.and(
            qb.compare('BioSam', :eq, b),
            qb.compare('Epitopes', :eq, 'WCE'),
            qb.compare('Reference Sequence', :eq, ref_seq)
        )
    })
    sorted_wces = wces.sort! { |wce1, wce2| wce_sort_fn(wce1, wce2) }
    most_recent_wce = sorted_wces.pop()

    input_control = nil

    wce_override = s.get('Input Control Override')
    bypass_rescaling = wce_override == 'bypass CNV rescaling step'

    if bypass_rescaling
        input_control = wce_override
    else
        wce = wce_override || most_recent_wce
    
        # const bypassCNVRescalingStep = a.wceOverride === bypassCNVRescalingStepName;

        # let cnvRatiosBed;
        # let inputControlName;
        # let isValidWorkflowReq = true;
    
        # if (bypassCNVRescalingStep) {
        #   inputControlName = bypassCNVRescalingStepName;
        # } else {
        #   const wce = a.wceOverride
        #     ? wceOverrides.get(a.wceOverride)
        #     : biosamWCEInputs.get(biosam);
        #   if (!wce) {
        #     failures.push({
        #       name: a.name,
        #       error: a.wceOverride
        #         ? `Input Control Override for ${a.name} doesn't exist: ${a.wceOverride}`
        #         : `${biosam} doesn't have any WCE(s), and no Input Control Override was set for ${a.name}`,
        #     });
        #     isValidWorkflowReq = false;
        #   } else {
        #     const isInputControl = a.name === wce.name;
        #     if (!isInputControl) {
        #       cnvRatiosBed = wce.cnvRatiosBed!;
        #       if (!wce.cnvRatiosBed) {
        #         failures.push({
        #           name: a.name,
        #           error: `${a.name} depends on WCE ${wce.name}, which is missing a CNV_Ratios_BED_URI`,
        #         });
        #         isValidWorkflowReq = false;
        #       }
        #     }
        #     inputControlName = wce.name;
        #   }
        # }
end

