require 'json'
require_script 'parse_xml'
require_script 'import_helpers'

# Load the XML file
file_path = params['Run Parameters File'].path
xml_file = File.read(file_path)

run_params = parse_run_params_xml(subjects, params, xml_file)

# Error checking
pa_without_lanes = subjects.find { |pa| pa.get_value('PA_Lanes').empty? }

if pa_without_lanes && !run_params[:lanes]
  raise_message("No lanes specified for #{pa_without_lanes.name}")
end

# File on prem to transfer
parent_path = params['text_attribute_for_tasks3']
bcl = File.join(parent_path, run_params[:folder_name])

candidate_molecular_barcodes = get_candidate_molecular_barcodes(
  params['Sequencing Schema'], 
  run_params[:instrument_model]
)
candidate_molecular_indices = get_candidate_molecular_indices()

# Assemble arguments for individual Pool Aliquot pipelines
pipelines = subjects.map do |pa|
  multiplexParams = pa['CoPA SBR'].map do |copa|
    get_multiplex_params(
      copa, 
      params['Sequencing Technology'], 
      run_params[:instrument_model]
    )
  end
  projects = pa['CoPA SBR'].map{ |copa| get_projects(copa) }.to_h
  pipeline = {
    lanes: pa.get_value('PA_Lanes').empty? ?
             run_params[:lanes] :
             pa.get_value('PA_Lanes').map(&:to_i),
    multiplexParams: multiplexParams,
    maxMismatches: run_params[:max_mismatches],
    minMismatchDelta: run_params[:min_mismatch_delta],
    outputJson: "gs://broad-epi-bcl-output-jsons/#{pa.id}.json",
    context: {
      poolAliquotUID: pa.id,
      projects: projects,
      sequencingTechnology: params['Sequencing Technology'],
      instrumentModel: run_params[:instrument_model],
      experimentName: run_params[:experiment_name],
      folderName: run_params[:folder_name],
      runDate: run_params[:run_date],
      genomeName: get_default_genome(params['text_attribute_for_tasks2']),
      lims7: true
    }.to_json
  }
  pipeline
end

# Assemble arguments for overall cromwell workflow submission
req = [{
    :workflow => 'chip-seq-import',
    :subj_name => subjects.map{ |s| s.name }.join(','),
    :subj_id => subjects.map{ |s| s.id }.join(','),
    # :on_hold => true,
    :bcl => bcl,
    :read_structure => run_params[:read_structure],
    :candidate_molecular_barcodes => candidate_molecular_barcodes,
    :candidate_molecular_indices => candidate_molecular_indices,
    :pipelines => pipelines,
}]

# show_message("#{req.to_json}")

Rails.logger.info("#{req.to_json}")

submit_jobs(req)