# This formats inputs for a share-seq import cromwell job

require 'json'
require_script 'import_helpers'
require_script 'submit_jobs'


# TODO Right now assumes a human (hg19) genome
genome = 'hg19'
sequencing_technology = 'SHARE-seq'
instrument_model = 'NovaSeq'


def insert_barcodes(barcodes, key, round_barcode_set, round_barcode_set_list)
    full_list = round_barcode_set_list.unshift(round_barcode_set.name.gsub(' ', '-'))
    if barcodes.key?(key)
        barcodes[key].append(full_list)
    else
        barcodes[key] = [full_list]
    end
end

def insert_copa_names(copa_names, key, name)
    fixed_name = name.gsub(' ', '-')
    if copa_names.key?(key)
        copa_names[key].append(fixed_name)
    else
        copa_names[key] = [fixed_name]
    end
end

# TODO this function is somewhat costly. We could offload some of the
# copa->map conversions to the server to save time. 
def format_pipeline_inputs(copas)
    # All pipeline inputs are grouped by unique combinations of
    # PKR and Library types
    round1_barcodes = {}
    round2_barcodes = {}
    round3_barcodes = {}
    copa_ids = {}
    pkr_barcode_groups = {}

    copas.each do |copa|
        # Grab all the required values per CoPA from the LIMS data model
        pc = copa.get_value('SS-PC')
        library_type = pc.get_value('SS_Library_Type')
        lib = pc.get_value('SS-Library')
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
        key = pkr.name.gsub(' ', '-') + '|' + library_type + '|' + lib_barcode.name

        # Barcode sequence for each key is always the same so it
        # doesn't matter if we overwrite it
        pkr_barcode_groups[key] = seq

        # Group round barcodes and copa names by this unique key
        insert_barcodes(round1_barcodes, key, copa, r1_list)
        insert_barcodes(round2_barcodes, key, r2, r2_list)
        insert_barcodes(round3_barcodes, key, r3, r3_list)

        insert_copa_names(copa_ids, key, copa.name)	
    end

    pkr_ids = []
    sample_types = []
    multiplex_params = []

    pkr_barcode_groups.each do |k, v|
        pkr_id, sample_type, barcode_name = k.split('|')
        pkr_ids.append(pkr_id)
        sample_types.append(sample_type)
        multiplex_params.append([barcode_name.gsub('_','-'), v])
    end

    # The final count of each of these arrays should be equal
    # to the number of unique PKR Library Type combinations
    return {
        :pkr_ids => pkr_ids,
        :sample_types => sample_types,
        :multiplex_params => multiplex_params,
        :round1_barcodes => round1_barcodes.values(),
        :round2_barcodes => round2_barcodes.values(),
        :round3_barcodes => round3_barcodes.values(),
        :copa_ids => copa_ids.values()
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
        ssCopas: pipeline_inputs[:copa_ids],
        pkrId: pipeline_inputs[:pkr_ids],
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

submit_jobs(req)
