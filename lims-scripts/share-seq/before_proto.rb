extend UI

bcl_names = subjects.map{ |s| s.get_value('SS-CoPA').get_value('SS-PA').get_value('HiSeq Folder Name') }
    .uniq

show_alert('Selected Lane Subsets come from different BCLs') if bcl_names.length > 1
table_name = bcl_names.length == 1 ? File.basename(bcl_names[0], '.*') : ""

params[:custom_fields] = UIUtils.encode_fields([
    field_set(
        title: "<b>Terra Workspace</b>",
        items: [
            field_container([
                udf(
                    'checkbox_for_tasks',
                    nil,
                    fieldLabel: 'Group by PKR only?',
                ),
                udf(
                    'HiSeq Folder Name',
                    nil,
                    fieldLabel: 'Terra Table Name',
                    required: true,
                    defaultValue: table_name,
                ),
                udf(
                    'text_attribute_for_tasks',
                    nil,
                    fieldLabel: 'Billing Project',
                    required: true,
                ),
                udf(
                    'text_attribute_for_tasks2',
                    nil,
                    fieldLabel: 'Workspace Name',
                    required: true,
                )
            ])
        ]
    )
])