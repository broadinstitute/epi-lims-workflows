# This formats inputs for a share-seq import cromwell job, which expects
# a request like this:
    # {
    #   "bcl": "gs://broad-epi-dev-ss-bcls/220718_SL-NVB_1001_AHGCF5DRX2.tar",
    #   "readStructure": "75T8B8B8B67T",
    #   "candidateMolecularBarcodes": {s
    #     "IDT8_i5_300": "TGTCTGCT",
    #     "IDT8_i5_301": "ATAAGGCG",
    #   },
    #   "candidateMolecularIndices": {
    #     "CBE103P.PT3-Ad_BC03": "ATACTTGG",
    #     "CBE111P.PT3-Ad_BC11": "ACTCTGGA",
    #   },
    #   "pipelines": [
    #     {
    #       "context": {
            #     "experimentName":"HGCF5DRX2",
            #     "folderName":"220718_SL-NVB_1001_AHGCF5DRX2",
            #     "genomeName":"hg19",
            #     "instrumentModel": "NovaSeq",
            #     "poolAliquotUID":509058,
            #     "projects":{"SS-CoPA 110":[],"SS-CoPA 111":[]},
            #     "runDate":"07/18/2022",
            #     "sequencingTechnology":"SHARE-seq"
            # },
    #       "lanes": [
    #         1,
    #         2
    #       ],
    #       "maxMismatches": 2,
    #       "minMismatchDelta": 2,
    #       "multiplexParams": [
    #         [
    #           "SS-CoPA 110",
    #           "AAGCACTG"
    #         ],
    #         [
    #           "SS-CoPA 111",
    #           "AAGCACTG"
    #         ],
    #       ],
    #       "outputJson": "gs://broad-epi-dev-bcl-output-jsons/509058.json",
    #       "pkrId": [],
    #       "sampleType": []
    #     }
    #   ]
    # }

require_script 'submit_jobs'

# TODO This will have to be extended for the regular import case
# but right now this only takes care of share-seq and assumes
# a human (hg19) genome
sequencing_technology = 'SHARE-seq'
genome = 'hg19'

def find_xml_value(key, xml)
    i1 = xml.index('<' + key + '>')
    i2 = xml.index('</' + key + '>')
    return xml[(i1 + key.length + 2)..(i2 - 1)]
end

def parse_run_date(run_date)
  year = '20' + run_date[0..2]
  month = run_date[2..2]
  day = run_date[4..2]
  return [month, day, year].join('/');
end

def parse_run_parameters(run_parameters_file)
    xml = File.read(run_parameters_file.path)
    return {
        folder_name: find_xml_value('RunID', xml),
        experiment_name: find_xml_value('ExperimentName', xml),
        instrument_model: 'NextSeq', # TODO
        read1: find_xml_value('Read1', xml),
        read2: find_xml_value('Read2', xml),
        index_read1: find_xml_value('Index1Read', xml),
        index_read2: find_xml_value('Index2Read', xml),
        max_mismatches: 1,  # TODO
        min_mismatch_delta: 1, # TODO
        run_date: parse_run_date(find_xml_value('RunStartDate', xml))
    }
end

# TODO ensure that nothing special needs to happen for share-seq
# This also doesn't work for ChIP or Mint-Chip currently, see after.rb
def get_read_structure(read1, read2, index_read1, index_read2)
    read_structure = [
        "#{read1}T",
        '8B',
        (index_read1 > 8 ? ["#{index_read1 - 8}S"] : []).flatten,
        (index_read2 >= 8 ? ['8B'] : []).flatten,
        (index_read2 > 8 ? ["#{index_read2 - 8}S"] : []).flatten,
    ]
    return [read_structure.flatten, '8B', "#{read2 - 8}T"].join(' ')
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

def get_multiplex_params()
    return coPAs.map(coPA => {
        const barcodes = [...coPA.barcodes];
        if (
          instrumentModel === 'NextSeq' &&
          ((barcodes.length === 2 && sequencingTechnology === 'ChIP') ||
            barcodes.length === 3)
        ) {
          barcodes[1] = reverseComplement(barcodes[1]);
        }
        return [coPA.name, ...barcodes];
      });
end

def get_candidate_molecular_indices()
    molecular_indexes = find_subjects(query:search_query(from:'ChrPrp Index') { |qb|
        qb.compare('ChrPrp Index In-Use', :eq, 'TRUE')
    })
    candidates = {}
    molecular_indexes.each{ |mi| candidates[mi.name] = mi.get_value('Molecular Barcode Index') }
    return candidates
end

def get_candidate_molecular_barcodes(sequencing_schema)
    molecular_barcodes = find_subjects(query:search_query(from:'Molecular Barcode') { |qb|
        qb.compare('Sequencing Schema', :eq, sequencing_schema)
    })
    candidates = {}
    molecular_barcodes.each{ |mb| candidates[mb.name] = mb.get_value('Molecular Barcode Sequence') }
    return candidates
end

def format_copa_parameters(copas)
    pkr_ids = []
    sample_types = []
    multiplex_params = []
    round1_barcodes = []
    round1_barcodes = []
    round1_barcodes = []

    # Grab all the required values per CoPA from the LIMS data model
    lib = copa.get_value('SS-PC').get_value('SS-Library')
    mo_lib = lib.get_value('MO scATAC Lib') ?
        lib.get_value('MO scATAC Lib') :
        lib.get_value('MO scRNA Lib')
    seq = mo_lib.get_value('Molecular Barcode')
        .get_value('Molecular Barcode Sequence')
    pkr = mo_lib.get_value('SS-PKR')
    sse = pkr.get_value('Share Seq Experiment')
    # Round 1 Barcode Set belongs to the library's Share Seq Experiment Component
    r1 = lib.get_value('SSEC').get_value('Round 1 barcode set')
    # Round 2 and 3 Barcode Sets belong to the MO Lib's Share Seq Experiment
    r2 = sse.get_value('Round 2 barcode set')
    r3 = sse.get_value('Round 3 barcode set')
    r1_list = r1.get_value('Round 2 Barcode Set Subject List')
        .map{ |rb| rb.get_value('Round 1 barcode sequence') }
    r2_list = r2.get_value('Round 2 Barcode Set Subject List')
        .map{ |rb| rb.get_value('Round 2 barcode sequence') }
    r3_list = r3.get_value('Round 3 Barcode Set Subject List')
        .map{ |rb| rb.get_value('Round 3 barcode sequence') }
    
    # Add to individual arrays
    pkr_ids.append(pkr.id)
    sample_types.append(lib.get_value('SS_Library_Type'))
    multiplex_params.append([copa.name, seq])
    # TODO I think I still have to cut up these arrays by plate...? 
    # or it's just an array<array<string>>
    round1_barcodes.append()
    round2_barcodes.append()
    round3_barcodes.append()

    return {
        :pkr_ids => pkr_ids,
        :sample_types => sample_types,
        :multiplex_params => multiplex_params,
        :round1_barcodes => round1_barcodes,
        :round2_barcodes => round2_barcodes,
        :round3_barcodes => round3_barcodes
    }
end

run_parameters = parse_run_parameters(params['Run Parameters File'])
read_structure = get_read_structure(
    run_parameters['read1']
    run_parameters['read2']
    run_parameters['index_read1']
    run_parameters['index_read2']
)
# copas = subj['SS-CoPA SBR'].map{|copa| format_copa(copa) }
pipeline_inputs = format_copa_parameters(subj['SS-CoPA SBR'])
candidate_molecular_indices = get_candidate_molecular_indices()
candidate_molecular_barcodes = get_candidate_molecular_barcodes(params['Sequencing Schema'])

# TODO I don't think r1 barcodes are showing up 
  # Example:
  # [
  #	  [ COPA1
  #     ["SS V1 RIGHT HALF", "AACCTTGG", "AAAATTTT", "ACTGACTG"],
  #     ["SS V1 LEFT HALF", "GGTTCCAA", "GGGGCCCC", "CAGTCAGT"]	
  #   ],
  #	  [ COPA2
  #     ["SS V2 RIGHT HALF", "AAAATTTT", "AACCTTGG", "ACTGACTG"],
  #     ["SS V2 LEFT HALF", "CAGTCAGT", "GGGGCCCC", "GGTTCCAA"]	
  #   ],
  # ]

submit_jobs([{
    :workflow => 'share-seq-import',
    :subj_name => subj.name,
    :subj_id => subj.id,
    :bcl => bcl,
    :read_structure => read_structure,
    # TODO this actually needs to be parsed by getWorkflowCandidateMolecularBarcodes
    :candidate_molecular_barcodes => candidate_molecular_barcodes,
    :candidate_molecular_indices => candidate_molecular_indices,
    # Note that we only allow SS-PA to be processed at a time, but
    # wdl expects multiple pipelines each corresponding to a subject
    :pipelines => [
        lanes: subj.get_value('lanes'),
        maxMismatches: 2, # TODO verify
        minMismatchDelta: 2, # TODO verify
        # Each entry in the following arrays correspond to a CoPA
        multiplexParams: pipeline_inputs['multiplex_params'],
        round1Barcodes: pipeline_inputs['round1_barcodes'],
        round2Barcodes: pipeline_inputs['round2_barcodes'],
        round3Barcodes: pipeline_inputs['round3_barcodes'],
        pkrId: pipeline_inputs['pkr_ids'],
        sampleType: pipeline_inputs['sample_types'],
        # TODO this gcs prefix should not be hardcoded
        outputJson: 'gs://broad-epi-dev-bcl-output-jsons/' + subj.id.to_s + '.json',
        context: {
            poolAliquotUID: subj.id,
            projects: [],
            sequencingTechnology: sequencing_technology,
            instrumentModel: run_parameters['instrument_model'],
            experimentName: run_parameters['experiment_name'],
            folderName: run_parameters['folder_name'],
            runDate: run_parameters['run_date'],
            genomeName: genome
        }
    ],
}])
