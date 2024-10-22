require 'set'
require_script 'submit_jobs'
require_script 'chip_helpers'

# Sort lane subsets by UID
subjects.sort! { |a, b| a.id <=> b.id }

# Additional metadata to be passed to workflow
donors = Set[]
segmenters = Set[]
instruments = Set[]
species_common_names = Set[]
cell_types = Set[]
epitopes = Set[]
projects = {}

# Format query params for each LS chipseq job
lane_subsets = subjects.map do |ls|
  pc = ls.get_value('Component of Pooled SeqReq')
    .get_value('CoPA')
    .get_value('Pool Component')
  sequencing_technology = pc.get_value('Pool of Libraries')
    .get_value('Sequencing Technology')
  lib = pc.get_value('Library')
  chip = lib.name.start_with?('Mint') ? lib
    .get_value('In Vitro Transcript')
    .get_value('MoIVT')
    .get_value('MoMint-ChIP') : lib.get_value('ChIP')
  epitope = chip.get_value('Antibody Aliquot')
    .get_value('Purchasable Antibody')
    .get_value('Epitope')
  segmenter = epitope.get_value('Preferred Segmenter')
    .map{ |pf| pf.gsub('HOMER -', '') }
  chrprp = lib.name.start_with?('Mint') ? lib
    .get_value('In Vitro Transcript')
    .get_value('Mint-ChIP')
    .get_value('CoMoChrPrp')
    .get_value('Chromatin Prep') : lib
    .get_value('ChIP')
    .get_value('Chromatin Prep')
  biosam = chrprp.get_value('BioSAli')
    .get_value('Biological Sample')
  project = biosam.get_value('Project')
  cell_type = biosam.get_value('Cell Type')
  donor = biosam.get_value('Donor')
  species_common_name = donor.get_value('Cohort')
    .get_value('Species Common Name').name
  lane = ls.get_value('LIMS_Lane')
  instrument = lane.get_value('Instrument Model')
  run_date = lane.get_value('Run End Date')

  description = "#{sequencing_technology}-Seq analysis of " \
    "#{epitope} in #{species_common_name} " \
    "#{cell_type} cells"

  donors.add(donor.name)
  instruments.add(parse_instrument_model(instrument))
  segmenters.add(segmenter)
  species_common_names.add(species_common_name)
  cell_types.add(cell_type)
  epitopes.add(epitope)
  projects[ls.name] = project.name
  
  # Format the lane subsets for workflow input
  lane_subset = {
    :name => ls.name,
    :sampleName => biosam.name,
    :libraryName => lib.name,
    :description => description,
    :sequencingCenter => 'BI', # Broad Institute
    :instrumentModel => parse_instrument_model(instrument),
    :runDate => parse_run_date(run_date),
    :fastqs => [
      ls['Reads 1 Filename URI'],
      ls['Reads 2 Filename URI']
    ].filter{ |f| f }
  }
end

req = [{
  :workflow => 'chipseq',
  :subj_name => subjects.map{ |s| s.name }.join(','),
  :subj_id => subjects.map{ |s| s.id }.join(','),
  :donor => get_prop(donors, 'Donor'),
  :genome_name => 'hg19', # TODO pass in from before
  :peak_styles => get_prop(segmenters, 'Preferred Segmenter'),
  :instrument_model => get_prop(instruments, 'Instrument Model'),
  :lane_subsets => lane_subsets,
  :context => {
    speciesCommonName: get_prop(species_common_names, 'Species Common Name'),
    cellTypes: cell_types.to_a.sort.join(';'),
    epitopes: epitopes.to_a.sort.join(';'),
    projects: projects,
    lims7: true
  }.to_json
}]

Rails.logger.info("#{req.to_json}")

# show_message("#{req.to_json}")

# Launch jobs
submit_jobs(req)