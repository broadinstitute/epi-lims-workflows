# Input subjects are Pool Aliquots

# NOTE This requires a file type UDF called Run Parameters File
# NOTE text_attributes_for_tasks is a dummy text variable
# allowing us to pass arbitrary text content, not necessarily
# bound to a UDF, to the after script

# TODO display values in form instead of putting them in form fields (or prevent user from changing value)

extend UI
require_script 'import_helpers'

# Fetch values for error checking
pas = subjects
pa_lanes = pas.flat_map{ |pa| pa.get_value('PA_Lanes') }.uniq.sort
copas = pas.flat_map{ |pa| pa['CoPA SBR'] }
pcs = copas.map{ |copa| copa.get_value('Pool Component') }
pools = pcs.map{ |pc| pc.get_value('Pool of Libraries') }
libraries = pcs.map{ |pc| pc.get_value('Library') }
molecular_barcodes = libraries.map do |lib| 
  lib.get_value('Molecular Barcode') || lib.get_value('MoMint_DNA_Lib')
                                           .get_value('Molecular Barcode')
end
chr_preps = libraries.map do |lib| 
  exp = lib.get_value('ChIP') || lib.get_value('In Vitro Transcript')
                                    .get_value('Mint-ChIP')
                                    .get_value('CoMoChrPrp')
  exp.get_value('Chromatin Prep')
end
chr_preps_idx = chr_preps.map{ |prep| prep.get_value('ChrPrp Index') }
cohorts = chr_preps.map{ |prep|
  prep.get_value('BioSAli')
      .get_value('Biological Sample')
      .get_value('Donor')
      .get_value('Cohort')
}

# Error checking
run_id = get_prop(pas, 'Pool Aliquot', 'HiSeqRun')
folder_name = get_prop(pas, 'Pool Aliquot', 'HiSeq Folder Name')
sequencing_technology = get_prop(pools, 'Pools of Libraries', 'Sequencing Technology')
sequencing_schema = get_prop(molecular_barcodes, 'Molecular Barcodes', 'Sequencing Schema')
species_common_name = get_prop(cohorts, 'Cohort', 'Species Common Name').name

check_missing_props(molecular_barcodes, 'Molecular Barcode Sequence')
case sequencing_technology
when 'ChIP'
  # Do nothing for 'ChIP'
when 'SHARE-seq'
  # Do nothing for 'SHARE-seq'
when 'Mint-ChIP'
  check_missing_props(chr_preps_idx, 'Molecular Index Sequence')
else
  raise_message("Unrecognized sequencing technology: #{sequencing_technology}")
end

pa_names = subjects.map(&:name).join(', ')

if run_id
  params[:tool_message] = <<~HTML
    <b style='color: red; font-size: larger;'>
      Displaying previously imported Pool Aliquot(s)
    </b>
  HTML
end

# Ex parent path = /seq/illumina_ext/SL-NXD/
params[:custom_fields] = UIUtils.encode_fields([
  field_set(
    title: "<b>Pool Aliquot(s): #{pa_names}</b>",
    items: [
      field_container([
        udf(
          'HiSeqRun',
          nil,
          fieldLabel: 'HiSeqRun',
          required: false,
          defaultValue: run_id
        ),
        udf(
          'HiSeq Folder Name',
          nil,
          fieldLabel: 'HiSeq Folder Name',
          required: false,
          defaultValue: folder_name
        ),
        udf(
          'Sequencing Technology',
          nil,
          fieldLabel: 'Sequencing Technology',
          required: true,
          defaultValue: sequencing_technology
        ),
        udf(
          'text_attribute_for_tasks2',
          nil,
          fieldLabel: 'Species Common Name',
          required: true,
          defaultValue: species_common_name
        ),
        udf(
          'Sequencing Schema',
          nil,
          fieldLabel: 'Sequencing Schema',
          required: true,
          readOnly: true,
          defaultValue: sequencing_schema
        )
      ])
    ]
  ),
  field_set(
    title: "<b>Run Parameters</b>",
    items: [
      field_container([
        # TODO possibly get rid of this - we might only be receiving
        # bcls from GCS now for share-seq
        udf(
          'text_attribute_for_tasks3',
          nil,
          fieldLabel: 'Parent path on NFS',
          required: true,
          defaultValue: 'Note: this may just be GCS'
        ),
        udf(
          'PA_Lanes',
          nil,
          fieldLabel: 'PA_Lanes',
          required: false,
          defaultValue: pa_lanes
        ),
        # NOTE this UDF has to be created in LIMS as a File type
        udf('Run Parameters File', nil, required: false)
      ])
    ]
  )
])

params[:skip_UDF] = {
    'HiSeqRun' => true,
    'HiSeq Folder Name' => true,
}