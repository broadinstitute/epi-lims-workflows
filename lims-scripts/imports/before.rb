# Input subjects are SS-Pool Aliquots

# NOTE This is only for Share-Seq right now and will have to be
# refactored to accommodate Chip-Seq as well 
# NOTE This requires a file type UDF called Run Parameters File
# NOTE text_attributes_for_tasks is a dummy text variable
# allowing us to pass arbitrary text content, not necessarily
# bound to a UDF, to the after script

# TODO check if import has already been run
# TODO display values in form instead of putting them in form fields (or prevent user from changing value)
# TODO handle validation across PA and CoPA - see queryBclImport
    # HiSeqRun, HiSeq_Folder_Name need to be the same across all PA
    # Sequencing_Technology, Species_Common_Name, Sequencing_Schema
    # need to be the same across all CoPA
    # Might need to do this in after script
# TODO include Alignment Genome

extend UI

# TODO assumes Human for now
species_common_name = 'Human'
ss_pool_component = subj['SS-CoPA SBR'][0]
    .get_value('SS-PC')
sequencing_technology = ss_pool_component
    .get_value('SS-Pool')
    .get_value('Sequencing Technology')
ss_library = ss_pool_component
    .get_value('SS-Library')
sequencing_schema = (ss_library.get_value('MO scATAC Lib') ? ss_library.get_value('MO scATAC Lib') : ss_library.get_value('MO scRNA Lib'))
    .get_value('Molecular Barcode')
    .get_value('Sequencing Schema')

pa_names = subjects.map{ |s| s.name }.join(', ')

# Ex parent path = /seq/illumina_ext/SL-NXD/
params[:custom_fields] = UIUtils.encode_fields([
    field_set(
        title: "<b>SS-Pool Aliquot(s): #{pa_names}</b>",
        items: [
            field_container([
                # udf(
                #     'HiSeqRun',
                #     nil,
                #     fieldLabel: 'HiSeqRun',
                #     required: false,
                #     defaultValue: subj['HiSeqRun']
                # ),
                udf(
                    'Data delivery bucket',
                    nil,
                    fieldLabel: 'Data delivery bucket',
                    required: true,
                    defaultValue: subj['Data delivery bucket']
                ),
                udf(
                    'HiSeq Folder Name',
                    nil,
                    fieldLabel: 'HiSeq Folder Name',
                    required: true,
                    defaultValue: subj['HiSeq Folder Name']
                ),
                udf(
                    'Sequencing Technology',
                    nil,
                    fieldLabel: 'Sequencing Technology',
                    required: true,
                    defaultValue: sequencing_technology
                ),
                udf(
                    'text_attribute_for_tasks',
                    nil,
                    fieldLabel: 'Species Common Name',
                    required: false,
                    defaultValue: species_common_name
                ),
                udf(
                    'Sequencing Schema',
                    nil,
                    fieldLabel: 'Sequencing Schema',
                    required: true,
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
                # udf(
                #     'text_attribute_for_tasks2',
                #     nil,
                #     fieldLabel: 'Parent path on NFS',
                #     required: false,
                #     defaultValue: 'Note: this may just be GCS'
                # ),
                # NOTE this UDF has to be created in LIMS as a File type
                udf('Run Parameters File', nil, required: false)
            ])
        ]
    )
])

# TODO Only display HiSeqRun and HiSeq Folder Name if they are present
params[:skip_UDF] = {
    'HiSeqRun' => true,
    'HiSeq Folder Name' => true,
}
