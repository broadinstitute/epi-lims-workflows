# NOTE This requires a file type UDF called Run Parameters File
# NOTE text_attributes_for_tasks is a dummy text variable
# allowing us to pass arbitrary text content, not necessarily
# bound to a UDF, to the after script

# TODO check if import has already been run
# TODO handle validation across PA and CoPA - see queryBclImport
    # HiSeqRun, HiSeq_Folder_Name need to be the same across all PA
    # Sequencing_Technology, Species_Common_Name, Sequencing_Schema
    # need to be the same across all CoPA
    # Might need to do this in after script
# TODO include Alignment Genome

extend UI

# These attributes should be the same across all CoPA
# so just grab the first one 
sequencing_technology = subj['CoPA SBR'][0]
    .get_value('Pool Component')
    .get_value('Pool of Libraries')
    .get_value('Sequencing Technology')

# TODO grab these values - might be able to use LIMS
# choice subjects instead of text_attribute udfs
species_common_name = 'Human'
sequencing_schema = 'Single Index Mint'

pa_names = subjects.map{ |s| s.name }.join(', ')

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
                    defaultValue: subj['HiSeqRun']
                ),
                udf(
                    'HiSeq Folder Name',
                    nil,
                    fieldLabel: 'HiSeq Folder Name',
                    required: false,
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
                    required: true,
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
                udf(
                    'text_attribute_for_tasks2',
                    nil,
                    fieldLabel: 'Parent path on NFS',
                    required: true
                ),
                udf('Run Parameters File', nil, required: true)
            ])
        ]
    )
])

# TODO Only display HiSeqRun and HiSeq Folder Name if they are present
params[:skip_UDF] = {
    'HiSeqRun' => true,
    'HiSeq Folder Name' => true,
}
