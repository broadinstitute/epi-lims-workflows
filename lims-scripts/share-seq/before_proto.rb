extend UI

params[:custom_fields] = UIUtils.encode_fields([
    field_set(
        title: "<b>Terra Workspace</b>",
        items: [
            field_container([
                udf(
                    'text_attribute_for_tasks1',
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