require 'set'
require_script 'submit_jobs'

# Sort lane subsets by UID
subjects.sort! { |a, b| a.id <=> b.id }

# Format query params for each LS chipseq job
lane_subsets = subjects.map do |ls|
    lib = ls.get_value('Component of Pooled SeqReq')
        .get_value('CoPA')
        .get_value('Pool Component')
        .get_value('Library')
    chip = lib.name.start_with?('Mint') ? lib
        .get_value('In Vitro Transcript')
        .get_value('MoIVT')
        .get_value('MoMint-ChIP') : lib.get_value('ChIP')
    segmenter = chip.get_value('Antibody Aliquot')
        .get_value('Purchasable Antibody')
        .get_value('Epitope')
        .get_value('Preferred Segmenter')
        .map{ |pf| pf.gsub('HOMER -', '') }
    chrprp = lib.name.start_with?('Mint') ? lib
        .get_value('In Vitro Transcript')
        .get_value('Mint-ChIP')
        .get_value('CoMoChrPrp')
        .get_value('Chromatin Prep') : lib.get_value('Chromatin Prep')
    biosam = chrprp.get_value('BioSAli')
        .get_value('Biological Sample')
    donor = biosam.get_value('Donor')
    lane = ls.get_value('LIMS_Lane')
    instrument = lane.get_value('Instrument Model')
    run_date = lane.get_value('Run End Date')
    
    # Format the lane subsets for workflow input
    lane_subset = {
        :name => ls.name,
        :sampleName => biosam.name,
        :libraryName => lib.name,
        :description => 'LANE SUBSET DESCRIPTION', # TODO 
        :sequencingCenter => 'BI', # Broad Institute
        :instrumentModel => instrument_model,
        :runDate => run_date, # TODO probably needs to be formatted correctly
        :fastqs => [
            ls['Reads 1 Filename URI'],
            ls['Reads 2 Filename URI']
        ].filter{ |f| f }
    }

    Rails.logger.info("******* #{lane_subset}")
end

# Launch jobs
submit_jobs({
    :workflow => 'chipseq',
    :subj_name => subjects.map{ |s| s.name }.join(','),
    :subj_id => subjects.map{ |s| s.id }.join(','),
    :donor => donors.to_a[0],
    :genome_name => 'hg19',
    :peak_styles => segmenters.to_a[0],
    :instrument_model => instruments.to_a[0],
    :lane_subsets => lane_subsets
})
