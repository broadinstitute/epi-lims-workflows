require 'json'
require_script 'submit_jobs'

def sanitize(string)
    return string.gsub(' ', '-').gsub('_','-')
end

def get_genome(species)
    genome = case species.downcase
        when /human/
            "hg38"
        when /mouse/
            "mm10"
        else
            raise "Error: Unknown species common name"
        end
    return genome
end

# For each LS, we want to return PKR, genome, R1_subset, 
# whitelist, atac_lib, R1/R2 fastqs, rna_lib, R1/R2 fastq

def format_pipeline_inputs(lane_subsets)
    
    # Initialize arrays
    pkr_names = []
    libraries = []
    copa_names = []
    sample_types = []
    genomes = []
    round1_subsets = []
    reads1 = []
    reads2 = []

    lane_subsets.each do |ls|
        # Grab all the required values per CoPA from the LIMS data model
        read1 = ls.get_value('Reads 1 Filename URI')
        read2 = ls.get_value('Reads 2 Filename URI')
        copa = ls.get_value('SS-CoPA')
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
        sample_type = atac ? 'ATAC' : 'RNA'
        mo_lib = atac || lib.get_value('MO scRNA Lib')
        lib_barcode = mo_lib.get_value('Molecular Barcode')
        pkr = atac ? mo_lib.get_value('SS-PKR') : mo_lib.get_value('MO cDNA').get_value('SS-PKR')
        sse = pkr.get_value('Share Seq Experiment')
        # Round 1 Barcode Set belongs to the library's Share Seq Experiment Component
        r1 = lib.get_value('SSEC').get_value('Round 1 barcode set')
 
        pkr_names.append(sanitize(pkr.name))
        libraries.append(sanitize(lib_barcode.name))
        copa_names.append(sanitize(copa.name))
        sample_types.append(sample_type)
        genomes.append(get_genome(spec.name))
        round1_subsets.append(sanitize(r1.name))
        reads1.append(read1)
        reads2.append(read2)
    end

    return {
        :pkr_names => pkr_names,
        :libraries => libraries,
        :copa_names => copa_names,
        :sample_types => sample_types,
        :genomes => genomes,
        :round1_subsets => round1_subsets,
        :reads1 => reads1,
        :reads2 => reads2
    }
end

pipeline_inputs = format_pipeline_inputs(subjects)


req = [{
    :workflow => 'share-seq-proto',
    :subj_name => subjects.map{ |s| s.name }.join(','),
    :subj_id => subjects.map{ |s| s.id }.join(','),
    :lane_subsets => [
        pkrIds: pipeline_inputs[:pkr_names],
        libraries: pipeline_inputs[:libraries],
        ssCopas: pipeline_inputs[:copa_names],
        sampleTypes: pipeline_inputs[:sample_types],
        genomes: pipeline_inputs[:genomes],
        round1Subsets: pipeline_inputs[:round1_subsets],
        reads1: pipeline_inputs[:reads1],
        reads2: pipeline_inputs[:reads2]
    ],
}]

show_message("#{req.to_json}")

# Rails.logger.info("#{req.to_json}")

# Launch jobs
# submit_jobs(req)
