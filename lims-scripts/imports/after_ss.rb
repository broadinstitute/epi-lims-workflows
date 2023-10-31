# This formats inputs for a share-seq import cromwell job

require 'json'
require_script 'import_helpers'
require_script 'submit_jobs'


# TODO Right now assumes a human (hg38) genome
genome = case params['text_attribute_for_tasks2'].downcase
    when "human"
        "hg38"
    when "mouse"
        "mm10"
    else
        raise "Error: Unknown species common name"
    end
sequencing_technology = 'SHARE-seq'
instrument_model = 'NovaSeq'

def sanitize(string)
    return string.gsub(' ', '-').gsub('_','-')
end

def insert_barcodes(barcodes, round_barcode_set, round_barcode_set_list)
    full_list = round_barcode_set_list.unshift(sanitize(round_barcode_set.name))
    barcodes.append([full_list])
end

# TODO this function is somewhat costly. We could offload some of the
# copa->map conversions to the server to save time. 
def format_pipeline_inputs(copas)
    # All pipeline inputs are grouped by unique combinations of
    # PKR and Library types
    round1_barcodes = []
    round2_barcodes = []
    round3_barcodes = []
    copa_names = []
    copa_map = []
    species = []
    pkr_names = []
    sample_types = []
    multiplex_params = []

    copas.each do |copa|
        # Grab all the required values per CoPA from the LIMS data model
        pc = copa.get_value('SS-PC')
        library_type = pc.get_value('SS_Library_Type')
        lib = pc.get_value('SS-Library')
        spec = lib.get_value('SSEC')
            .get_value('BioSAli')
            .get_value('Biological Sample')
            .get_value('Donor')
            .get_value('Cohort')
            .get_value('Species Common Name')
        atac = lib.get_value('MO scATAC Lib')
        mo_lib = atac || lib.get_value('MO scRNA Lib')
        lib_barcode = mo_lib.get_value('Molecular Barcode')
        seq = lib_barcode.get_value('Molecular Barcode Sequence')
        pkr = atac ? mo_lib.get_value('SS-PKR') : mo_lib.get_value('MO cDNA').get_value('SS-PKR')
        sse = pkr.get_value('Share Seq Experiment')
        # Round 1 Barcode Set belongs to the library's Share Seq Experiment Component
        r1 = lib.get_value('SSEC').get_value('Round 1 barcode set')
        # Round 2 and 3 Barcode Sets belong to the MO Lib's Share Seq Experiment
        r2 = sse.get_value('Round 2 barcode set')
        r3 = sse.get_value('Round 3 barcode set')
        r1_list = r1.get_value('Round 1 Barcode Set Subject List')
            .map{ |rb| rb.get_value('Round 1 barcode sequence') }
        r2_list = r2.get_value('Round 2 Barcode Set Subject List')
            .map{ |rb| rb.get_value('Round 2 barcode sequence') }
        r3_list = r3.get_value('Round 3 Barcode Set Subject List')
            .map{ |rb| rb.get_value('Round 3 barcode sequence') }

        # Unique pkr-library combination
        # key = pkr.name.gsub(' ', '-') + '|' + library_type + '|' + lib_barcode.name

        # Barcode sequence for each key is always the same so it
        # doesn't matter if we overwrite it
        # pkr_barcode_groups[key] = seq

        # Group round barcodes and copa names by this unique key
        insert_barcodes(round1_barcodes, r1, r1_list)
        insert_barcodes(round2_barcodes, r2, r2_list)
        insert_barcodes(round3_barcodes, r3, r3_list)

        copa_names.append(copa.name)
        copa_map.append([sanitize(lib_barcode.name) + '_' + sanitize(r1.name), copa.name])
        species.append(spec.name)
        pkr_names.append(pkr.name)	
        sample_types.append(library_type)
        multiplex_params.append([sanitize(lib_barcode.name), seq])
    end

    # pkr_barcode_groups.each do |k, v|
    #     pkr_id, sample_type, barcode_name = k.split('|')
    #     pkr_ids.append(pkr_id)
    #     sample_types.append(sample_type)
    #     multiplex_params.append([barcode_name.gsub('_','-'), v])
    # end

    # The final count of each of these arrays should be equal
    # to the number of unique PKR Library Type combinations
    return {
        :pkr_names => pkr_names,
        :sample_types => sample_types,
        :multiplex_params => multiplex_params,
        :round1_barcodes => round1_barcodes,
        :round2_barcodes => round2_barcodes,
        :round3_barcodes => round3_barcodes,
        :copa_names => copa_names,
        :copa_map => copa_map,
        :species => species
    }
end

pipeline_inputs = format_pipeline_inputs(subj['SS-CoPA SBR'])
# run_parameters = parse_run_parameters(params['Run Parameters File'], sequencing_technology)
candidate_molecular_indices = get_candidate_molecular_indices()
candidate_molecular_barcodes = get_candidate_molecular_barcodes(params['Sequencing Schema'])

req = [{
    :workflow => 'share-seq-import',
    :subj_name => subj.name,
    :subj_id => subj.id,
    :bcl => params['HiSeq Folder Name'],
    :bucket => params['Data delivery bucket'],
    :zipped => params['text_attribute_for_tasks'],
    :candidate_molecular_barcodes => candidate_molecular_barcodes,
    :candidate_molecular_indices => candidate_molecular_indices,
    # Note that wdl expects multiple pipelines for multiple SS-PA
    # but we only allow 1 SS-PA to be processed at a time
    :pipelines => [
        lanes: subj.get_value('PA_Lanes'),
        multiplexParams: pipeline_inputs[:multiplex_params],
        round1Barcodes: pipeline_inputs[:round1_barcodes],
        round2Barcodes: pipeline_inputs[:round2_barcodes],
        round3Barcodes: pipeline_inputs[:round3_barcodes],
        ssCopas: pipeline_inputs[:copa_names],
        # copaMap: pipeline_inputs[:copa_map],
        # species: pipeline_inputs[:species],
        pkrId: pipeline_inputs[:pkr_names],
        sampleType: pipeline_inputs[:sample_types],
        # TODO this gcs prefix should not be hardcoded
        outputJson: 'gs://broad-epi-workflow-outputs/' + subj.id.to_s + '.json',
        context: {
            poolAliquotUID: subj.id,
            projects: [],
            sequencingTechnology: sequencing_technology,
            instrumentModel: instrument_model,
            # experimentName: run_parameters[:experiment_name],
            # folderName: run_parameters[:folder_name],
            # runDate: run_parameters[:run_date],
            genomeName: genome
        }.to_json
    ],
}]
Rails.logger.info("#{req.to_json}")

# submit_jobs(req)
