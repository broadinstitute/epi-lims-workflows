require 'json'
require_script 'submit_jobs'

sequencing_technology = '10X'
instrument_model = 'NovaSeq X'

# def map_barcode_to_order(str)
#   char = str[-2].upcase # Get second-to-last character
#   pos = char.ord - 'A'.ord + 1
#   pos.odd? ? 1 : 2
# end

# copas = subjects.map{ |s| s.get_value('10X-CoPA') }
copas = find_subjects(query:search_query(from:'10X-CoPA') { |ls|
  ls.compare('"10X-PA"->name', :eq, subj.name)
  }, limit:30000)

samples = []
types = []
 
copas.each do |copa|
  pc = copa.get_value('10X-PC')
  library_type = pc.get_value('10X_Library_Type').sub(/^10X_/, "")
  lib = pc.get_value('10X-Library')
  lib_barcode = lib.get_value('10X_SI_barcode') || lib.get_value('10X_DI_barcode')
  
  # preamp = lib.get_value('10X_preAMP') || lib.get_value('10X_cDNA_Lib')
  #                                            .get_value('10X_preAMP')
  # mec = preamp.get_value('10X_MEC')
  # biosali = mec.get_value('BioSAli')
  
  # id = biosali.name.gsub(' ', '_') + '_' + 
  #     map_barcode_to_order(lib_barcode.name).to_s + '_' +
  #     library_type
  id = copa.name.gsub(' ', '-')
  
  if library_type == "GEX"
    barcode1 = lib_barcode.get_value('10X_index(i7)')
    barcode2 = lib_barcode.get_value('10X_index2_workflow_a(i5)')
    samples.append([id, barcode1, barcode2])
  elsif library_type == "ATAC"
    barcodes = lib_barcode.get_value('10X_i7_concatenated_index').split("_")
    barcodes.each do |barcode|
      samples.append([id, barcode])
    end 
  else
    raise_message("Error: Unknown library type: #{tech}")
  end
  types.append(library_type)
end

if types.uniq.length != 1
  raise_message("Error: Library types are not identical")
end

# Assemble arguments for overall cromwell workflow submission
req = [{
  :workflow => '10x-import',
  :subj_name => subj.name,
  :subj_id => subj.id,
  :bcl => params['HiSeq Folder Name'],
  :bucket => params['Data delivery bucket'],
  :lib_type => types.first,
  :lanes => subj.get_value('PA_Lanes').map(&:to_i),
  :samples => samples,
  :context => {
    poolAliquotUID: subj.id,
    projects: [],
    sequencingTechnology: sequencing_technology,
    instrumentModel: instrument_model,
    # experimentName: run_parameters[:experiment_name],
    # folderName: run_parameters[:folder_name],
    # runDate: run_parameters[:run_date],
  }.to_json
}]

Rails.logger.info("#{req.to_json}")

# show_message("#{req.to_json}")

submit_jobs(req)