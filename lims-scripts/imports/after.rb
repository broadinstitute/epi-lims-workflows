# TODO ensure RunParameters.xml has the same run ID as
# the one supplied in before script
# TODO implement parsing - LIMS exposes ruby xml parser
# imported at the top

require "rexml/document"
require_script 'submit_jobs'

def get_read_structure(seq_technology, read1, read2, index_read1, index_read2)
    read_structure = [
      "#{read1}T",
      '8B',
      (index_read1 > 8 ? ["#{index_read1 - 8}S"] : []).flatten,
      (index_read2 >= 8 ? ['8B'] : []).flatten,
      (index_read2 > 8 ? ["#{index_read2 - 8}S"] : []).flatten,
    ]
    if seq_technology == 'ChIP'
        return [
            read_structure.flatten,
            (read2 ? ["#{read2}T"] : []).flatten
        ].join(' ')
    end
    # TODO Mint-ChIP
    # if read2 <= 8
    #     throw Error('Read2 must be > 8')
    # end
    return [read_structure.flatten, '8B', "#{read2 - 8}T"].join(' ')
end

# TODO implement parsing and remove hardcoded values
def parse_inputs(xml)
    return {
        folder_name: '220424_SL-NXD_0685_AHJJ3WBGXL',
        experiment_name: '',
        instrument_model: 'NextSeq',
        read1: 30,
        read2: 30,
        index_read1: 99,
        index_read2: 8,
        max_mismatches: 1,
        min_mismatch_delta: 1
    }
end

def get_candidate_molecular_barcodes(sequencing_schema)
    molecular_barcodes = find_subjects(query:search_query(from:'Molecular Barcode') { |qb|
        qb.compare('Sequencing Schema', :eq, sequencing_schema)
    })
    candidates = {}
    molecular_barcodes.each{ |mb| candidates[mb.name] = mb.get_value('Molecular Barcode Sequence') }
    return candidates
end

def get_candidate_molecular_indices()
    molecular_indexes = find_subjects(query:search_query(from:'ChrPrp Index') { |qb|
        qb.compare('ChrPrp Index In-Use', :eq, 'TRUE')
    })
    candidates = {}
    molecular_indexes.each{ |mi| candidates[mi.name] = mi.get_value('Molecular Barcode Index') }
    return candidates
end

def reverse_complement(barcode)
    bases = {
      A: 'T',
      T: 'A',
      C: 'G',
      G: 'C',
      N: 'N',
    }
    return barcode
      .split('')
      .reverse()
      .map{ |base| bases[base] }
      .join('')
end

def get_barcodes(copa, seq_technology, instrument_model)
    library = copa
        .get_value('Pool Component')
        .get_value('Library')
    molecular_barcode = library
        .get_value('Molecular Barcode')
        .get_value('Molecular Barcode Sequence')
    if seq_technology == 'Mint-ChIP'
        molecular_index_sequence = library
            .get_value('ChrPrp')
            .get_value('ChrPrp Index')
            .get_value('Molecular Index Sequence')
    else
        molecular_index_sequence = ''
    end
    barcodes = [
        molecular_barcode,
        molecular_index_sequence
    ]
    if instrument_model == 'NextSeq' &&
        ((barcodes.length() == 2 && seq_technology == 'ChIP') || barcodes.length() == 3)
        barcodes[1] = reverse_complement(barcodes[1])
    end
    return barcodes.map{ |b| [copa.name, b] }
end

file = File.new(params['Run Parameters File'].path)
doc = REXML::Document.new file
run_params = parse_inputs(doc)

seq_technology = params['Sequencing Technology']
read_structure = get_read_structure(
    seq_technology,
    run_params[:read1],
    run_params[:read2],
    run_params[:index_read1],
    run_params[:index_read2]
)

# File on prem to transfer
parent_path = params['text_attribute_for_tasks2']
bcl = File.join(parent_path, run_params[:folder_name])

candidate_molecular_barcodes = get_candidate_molecular_barcodes(params['Sequencing Schema'])
candidate_molecular_indices = seq_technology == 'Mint-ChIP' ? get_candidate_molecular_indices() : {}

# TODO debug - this is causing script to silently fail
# Assemble arguments for individual Pool Aliquot pipelines
# pipelines = subjects.map do |pa|
#     barcodes = pa['CoPA SBR'].map do |copa|
#         return get_barcodes(
#             copa,
#             seq_technology,
#             run_params[:instrument_model]
#         )
#     end 
#     return {
#         lanes: pa['PA_Lanes'],
#         # multiplex_params: barcodes.flatten,
#         multiplex_params: [],
#         max_mismatches: run_params[:max_mismatches],
#         min_mismatch_delta: run_params[:min_mismatch_delta]
#     }
# end

# Assemble arguments for overall cromwell workflow submission
submit_jobs([{
    :workflow => 'import',
    :subj_name => subjects.map{ |s| s.name }.join(','),
    :subj_id => subjects.map{ |s| s.id }.join(','),
    :bcl => bcl,
    :read_structure => read_structure,
    :candidate_molecular_barcodes => candidate_molecular_barcodes,
    :candidate_molecular_indices => candidate_molecular_indices,
    # :pipelines => pipelines,
    :pipelines => [],
}])
