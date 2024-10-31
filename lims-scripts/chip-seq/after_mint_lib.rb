require_script 'submit_jobs'
require_script 'chip_helpers'
require_script 'chip_formatter'

genome = params['text_attribute_for_tasks']
validate_genome(genome)

req = subjects.flat_map do |subject|
  # For each subject, get lane subsets and format request
  samples = find_subjects(query:search_query(from:'Lane Subset') { |qb| 
      qb.and( 
        qb.compare('"Component of Pooled SeqReq"->"CoPA"->' +
          '"Pool Component"->"Library"["Mint_DNA_Lib"]->name', :eq, subject.name), 
        qb.compare('terminated', :eq, false) 
      ) 
    }, limit:1000
  ) 

  # Add aggregation to context
  aggregation = {
    name: subject.name,
    type: 'Mint_DNA_Lib',
    uid: subject.id
  }

  format_req(samples, genome, aggregation: aggregation)
end

Rails.logger.info("#{req.to_json}")

# show_message("#{req.to_json}")

# Launch jobs
submit_jobs(req)