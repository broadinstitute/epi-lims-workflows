extend UI

params[:tool_message] = <<~HTML
    <b style='color: black; font-size: larger;'>
      Enter Reference Genome Name
    </b>
  HTML

params[:custom_fields] = UIUtils.encode_fields([
  field_set(
    items: [
      field_container([
        udf(
          'text_attribute_for_tasks',
          nil,
          fieldLabel: 'Genome Name',
          required: true,
        )
      ])
    ]
  )
])