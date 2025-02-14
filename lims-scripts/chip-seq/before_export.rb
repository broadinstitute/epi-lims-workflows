extend UI

pas = subjects.flat_map do |s|
  find_subjects(query:search_query(from:'Pool Aliquot') { |pa|
    pa.compare('"CoP SeqReq SBR"->"CoPA"->"Pool Component"->name', :eq, s.name)
  }, limit:30000)
end

bcl_names = pas.map{ |pa| pa.get_value('HiSeq Folder Name')}.uniq

show_alert('Selected Lane Subsets come from different BCLs') if bcl_names.uniq.length > 1
table_name = bcl_names.uniq.length == 1 ? File.basename(bcl_names[0], '.*') : ""

params[:custom_fields] = UIUtils.encode_fields([
    field_set(
        title: "<b>Terra Workspace</b>",
        items: [
            field_container([
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