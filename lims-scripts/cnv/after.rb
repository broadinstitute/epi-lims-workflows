# Input subjects are Alignment Post Processing(s)

extend UI
require 'json'
require_script 'cnv_helpers'
require_script 'submit_jobs'

# Error checking across input APPs
ref_seqs = subjects.map { |app| app['Reference Sequence'] }.uniq
if ref_seqs.length > 1
  raise_message("Error: Reference Sequences for input APPs must be the same")
end

query_params = []

# Each subject is an APP
subjects.each do |app|
  ref_seq = app['Reference Sequence']

  if ref_seq == nil
    raise_message("Error: Reference Sequence is missing for #{app.name}")
    return
  end
  if app['BAM Filename URI'] == nil
    raise_message("Error: BAM Filename URI is missing for #{app.name}")
    return
  end

  biosams = app['Input_Alignments_SL'].map do |al| 
    lib = get_library(al)
    get_biosam(lib)
  end

  if biosams.uniq.length > 1
    raise_message("Error: Alignments for #{app.name} must come from exactly 1 BioSam" )
  end

  library = get_library(app['Input_Alignments_SL'][0])
  biosam = get_biosam(library).name

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
        raise_message("Error: Input Control Override for #{app.name} doesn't exist: #{wce_override}")
        return
      end
      raise_message("Error: #{biosam} doesn't have any WCE(s), and no Input Control Override was set for #{app.name}")
      return
    end
    
    is_input_control = app.name == wce.name
    if !is_input_control
      if !wce['CNV Ratios BED URI']
        raise_message("Error: #{app.name} depends on WCE #{wce.name}, which is missing a CNV Ratios BED URI")
        return
      end
      cnv_ratios_bed = wce['CNV Ratios BED URI']
    end

    input_control = wce.name
  end
  
  query_params.push({
    :workflow => 'cnv',
    :subj_name => app.name,
    :subj_id => app.id,
    :bam => app['BAM Filename URI'],
    :cnv_ratios_bed => cnv_ratios_bed,
    :genome_name => ref_seq.name.gsub('_picard', ''),
    :bypass_rescaling => bypass_rescaling,
    :context => {
      uid: app.id,
      inputControlName: input_control,
      lims7: true
    }.to_json
  })
end

# show_message("#{query_params.to_json}")
submit_jobs(query_params)