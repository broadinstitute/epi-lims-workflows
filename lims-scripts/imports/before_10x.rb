# Input subjects are 10X-Pool Aliquots

extend UI

pa_names = subjects.map{ |s| s.name }.join(', ')

params[:custom_fields] = UIUtils.encode_fields([
    field_set(
        title: "<b>10X-Pool Aliquot(s): #{pa_names}</b>",
        items: [
            field_container([
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
                )
            ])
        ]
    )
])
