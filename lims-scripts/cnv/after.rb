# Input subjects are Alignment Post Processing(s)

extend UI

require 'set'
require_script 'show_error'
require_script 'submit_jobs'

def wce_sort_fn(a, b)
    a[:updated_at] == b[:updated_at] ? a[:id] - b[:id] : (a[:updated_at] <= b[:updated_at] ? -1 : 1)
end

def get_library(app)
    alignment = app['Input_Alignments_SL'][0]
    return alignment
        .get_value('Lane Subset')
        .get_value('Component of Pooled SeqReq')
        .get_value('CoPA')
        .get_value('Pool Component')
        .get_value('Library')
end

def get_biosam(library)
    if library.name.include? 'Mint'
        return library
            .get_value('In Vitro Transcript')
            .get_value('Mint-ChIP')
            .get_value('CoMoChrPrp')
            .get_value('Chromatin Prep')
            .get_value('BioSAli')
            .get_value('Biological Sample')
    end
    return library
        .get_value('ChIP')
        .get_value('Chromatin Prep')
        .get_value('BioSAli')
        .get_value('Biological Sample')
    # TODO case for neither?
end

def get_alignments(library, biosam)
    if library.name.include? 'Mint'
        return biosam.get_value('Alignment SBR (BioSam) (Mint-ChIP)')
    end
    return biosam.get_value('Alignment SBR (BioSam) (ChIP)')
end

# TODO for some reason find_subjects complains the results
# are too large without a limit parameter, even though
# there are only ~3k results at time of comment
def get_wces(ref_seq, library, biosam)
    # TODO Could be precomputed to save time
    wce_apps = find_subjects(query:search_query(from:'Alignment Post Processing') { |app|
        app.and(
            app.compare('Epitopes', :eq, 'WCE'),
            app.compare('Reference Sequence', :eq, ref_seq)
        )
    }, limit:30000)

    # TODO could be precomputed to save time
    wce_alignments = Set[]
    wce_alignment_to_app = {}
    wce_apps.each do |app|
        app['Input_Alignments_SL'].each do |al|
            wce_alignments.add(al)
            if wce_alignment_to_app.include?(al.name)
                wce_alignment_to_app[al.name].add(app)
            else
                wce_alignment_to_app[al.name] = Set[app]
            end
        end
    end
    
    # This is a way to efficiently get WCE Apps by finding
    # the intersection of wce alignments and alignments
    # associated with the current biosam. Otherwise requires
    # traveling from alignment to biosam for each alignment,
    # which is very inefficient in lims
    alignments = get_alignments(library, biosam)
        .to_set
        .intersection(wce_alignments)

    # Get corresponding APPs
    apps = []
    alignments
      .map{ |a| wce_alignment_to_app[a.name] }
      .each do |app_set|
        app_set.each do |app|
          apps.push({
            :biosam => biosam,
            :id => app.id,
            :name => app.name,
            :updated_at => app.updated_at,
            :cnv_ratios_bed => app['CNV Ratios BED URI']
          })
        end
      end

    return apps
end

query_params = []

# Each subject is an APP
subjects.each do |app|
    ref_seq = app['Reference Sequence']

    if ref_seq == nil
        show_error("Reference Sequence is missing for #{app.name}")
        return
    end
    if app['BAM Filename URI'] == nil
        show_error("BAM Filename URI is missing for #{app.name}")
        return
    end

    library = get_library(app)
    biosam = get_biosam(library)

    # Get most recent WCE 
    wces = get_wces(ref_seq, library, biosam)
    sorted_wces = wces.sort! { |wce1, wce2| wce_sort_fn(wce1, wce2) }
    most_recent_wce = sorted_wces.length() > 0 ? sorted_wces.pop() : nil

    # Define the input control. If CNV rescaling step isn't bypassed,
    # it's either the Input Control Override specified in lims or the
    # most recent WCE APP associated with this APP's BioSam
    input_control = nil
    cnv_ratios_bed = nil

    wce_override = app['Input Control Override']
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
                show_error("Input Control Override for #{app.name} doesn't exist: #{wce_override}")
                return
            end
            show_error("#{biosam} doesn't have any WCE(s), and no Input Control Override was set for #{app.name}")
            return
        end
        
        is_input_control = app.name == wce[:name]
        if !is_input_control
            if !wce['cnv_ratios_bed']
                show_error("#{app.name} depends on WCE #{wce[:name]}, which is missing a CNV Ratios BED URI")
                return
            end
            cnv_ratios_bed = wce['cnv_ratios_bed']
        end

        input_control = wce[:name]
    end
    
    query_params.push({
        :workflow => 'cnv',
        :subj_name => app.name,
        :subj_id => app.id,
        :bam => app['BAM Filename URI'],
        :cnv_ratios_bed => cnv_ratios_bed,
        :genome_name => ref_seq.name.gsub('_picard', ''),
        :bypass_rescaling => bypass_rescaling,
        :input_control => input_control
    })
end

submit_jobs(query_params)
