require 'json'
require_script 'cnv_helpers'
require_script 'submit_jobs'

def sanitize(string)
    return string.gsub(' ', '-').gsub('_','-')
end

def get_chrprp(library)
  if library.name.include? 'Mint'
    return library
      .get_value('In Vitro Transcript')
      .get_value('Mint-ChIP')
      .get_value('CoMoChrPrp')
      .get_value('Chromatin Prep')
  end
  return library
    .get_value('ChIP')
    .get_value('Chromatin Prep')
end

def get_lss(pc)
  lane_subsets = find_subjects(query:search_query(from:'Lane Subset') { |ls|
    ls.compare('"Component of Pooled SeqReq"->"CoPA"->"Pool Component"->name', :eq, pc.name)
  }, limit:30000)
  return lane_subsets
end

def format_pipeline_inputs(pool_component)
  lib = pool_component.get_value('Library')
  epitope = lib.get_value('ChIP')
    .get_value('Antibody Aliquot')
    .get_value('Purchasable Antibody')
    .get_value('Epitope')
  chrprp = get_chrprp(lib)

  wce_pcs = find_subjects(query:search_query(from:'Pool Component') { |pc|
    pc.and(
      pc.compare('"Library"["DNA_Lib"]->"ChIP"->"Antibody Aliquot"->"Purchasable Antibody"->"Epitope"->name', :eq, "WCE"),
      pc.or(
        pc.compare('"Library"["DNA_Lib"]->"ChIP"->"Chromatin Prep"->name', :eq, chrprp.name),
        pc.compare('"Library"["Mint_DNA_Lib"]->"In Vitro Transcript"->"Mint-ChIP"->"CoMoChrPrp"->"Chromatin Prep"->name', :eq, chrprp.name)
      )
    )
  }, limit:30000)

  # Initialize arrays
  reads1 = []
  reads2 = []
  ctrl_r1 = []
  ctrl_r2 = []

  lane_subsets = get_lss(pool_component)
  lane_subsets.each do |ls|
    read1 = ls.get_value('Reads 1 Filename URI')
    read2 = ls.get_value('Reads 2 Filename URI')
    reads1.append(read1)
    reads2.append(read2)
  end

  wce_pcs.each do |wce_pc|
    r1 = []
    r2 = []
    get_lss(wce_pc).each do |ls|
      read1 = ls.get_value('Reads 1 Filename URI')
      read2 = ls.get_value('Reads 2 Filename URI')
      r1.append(read1)
      r2.append(read2)
    end
    ctrl_r1.append(r1.sort_by(&:downcase))
    ctrl_r2.append(r2.sort_by(&:downcase))
  end

  return {
    :libraries => sanitize(lib.name),
    :epitopes => epitope.name,
    :reads1 => reads1.sort_by(&:downcase),
    :reads2 => reads2.sort_by(&:downcase),
    :ctrl_r1 => ctrl_r1,
    :ctrl_r2 => ctrl_r2
  }
end

req = [{
    :workflow => 'chip-seq-export',
    :subj_name => subjects.map{ |s| s.name }.join(','),
    :subj_id => subjects.map{ |s| s.id }.join(','),
    :table_name =>  File.basename(params['HiSeq Folder Name'], ".*"),
    :terra_project => params['text_attribute_for_tasks'],
    :workspace_name => params['text_attribute_for_tasks2'],
    :pool_components => subjects.map{ |s| format_pipeline_inputs(s) }
}]

# show_message("#{req.to_json}")

Rails.logger.info("#{req.to_json}")

# Launch jobs
submit_jobs(req)