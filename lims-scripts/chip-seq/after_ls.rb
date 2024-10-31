require_script 'submit_jobs'
require_script 'chip_helpers'
require_script 'chip_formatter'

genome = params['text_attribute_for_tasks']
validate_genome(genome)

req = format_req(subjects, genome)

Rails.logger.info("#{req.to_json}")

# show_message("#{req.to_json}")

# Launch jobs
submit_jobs(req)