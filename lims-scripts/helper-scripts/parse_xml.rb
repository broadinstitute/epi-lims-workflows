require 'rexml/document'
require 'rexml/xpath'

def parse_run_params_xml(subjects, params, xml)
  doc = REXML::Document.new(xml)

  data = {}
  data[:run_id] = parse_integer(doc, ['//ScanNumber', '//RunNumber'])

  if params['HiSeqRun'] && params['HiSeqRun'].to_i != data[:run_id]
    raise_message("runParameters.xml has a different Run ID: #{data[:run_id]}")
  end

  data[:folder_name] = parse_string(doc, ['//RunID', '//RunId'])
  data[:experiment_name] = parse_string(doc, ['//ExperimentName', '//RunID', '//RunId'])
  data[:instrument_model] = get_instrument_model(doc)
  data[:run_date] = parse_run_date(doc, ['//RunStartDate'])

  if subjects.length == 1 && params['PA_Lanes'].nil?
    length = parse_string(doc, ['//NumLanes', 'count(//Lane)'], /^[1-9]\d*$/).to_i
    data[:lanes] = (1..length).to_a
  end

  # Read structure
  read1 = parse_integer(
    doc, 
    ['//Read1', '//Read1NumberOfCycles', info_read('N', 1)]
  )
  read2 = parse_integer(
    doc, 
    ['//Read2', '//Read2NumberOfCycles', info_read('N', 2)]
  )
  index_read1 = parse_integer(
    doc, 
    ['//IndexRead1', '//IndexRead1NumberOfCycles', '//Index1Read', info_read('Y', 1)]
  )
  index_read2 = parse_integer(
    doc, 
    ['//IndexRead2', '//IndexRead2NumberOfCycles', '//Index2Read', info_read('Y', 2)]
  )
  data[:read_structure] = get_read_structure(
    params['Sequencing Technology'], read1, read2, index_read1, index_read2
  )

  is_chip = params['Sequencing Technology'] == 'ChIP'
  data[:max_mismatches] = is_chip ? '1' : '2'
  data[:min_mismatch_delta] = is_chip ? '1' : '2'

  data
end

def parse_string(doc, xpaths, regex = /.+/)
  result = ''
  xpaths.each do |xpath|
    REXML::XPath.each(doc, xpath) do |element|
      result = element.text
      break if result != ''
    end
    break if result != ''
  end

  unless regex.match?(result)
    raise_message("Could not parse value from provided xpaths")
  end

  result
end

def parse_integer(doc, xpaths)
  parse_string(doc, xpaths, /^\d+$/).to_i
end

def get_instrument_model(doc)
  app_name = parse_string(doc, ['//ApplicationName', '//Application'])
  match = /(\w+Seq)/.match(app_name)
  unless match
    raise_message('Could not parse Instrument Model from ApplicationName')
  end
  match[0]
end

def parse_run_date(doc, xpaths)
  run_date = parse_string(doc, xpaths, /^\d{6}$/)
  year = "20#{run_date[0..1]}"
  month = run_date[2..3]
  day = run_date[4..5]
  "#{month}/#{day}/#{year}"
end

def get_read_structure(sequencing_technology, read1, read2, index_read1, index_read2)
  read_structure = ["#{read1}T", '8B']
  read_structure << "#{index_read1 - 8}S" if index_read1 > 8
  read_structure << '8B' if index_read2 >= 8
  read_structure << "#{index_read2 - 8}S" if index_read2 > 8

  if sequencing_technology == 'ChIP'
    read_structure << "#{read2}T" if read2 > 0
  else
    raise_message('Read2 must be > 8') if read2 <= 8
    read_structure << '8B'
    read_structure << "#{read2 - 8}T"
  end

  read_structure.join('')
end

def info_read(is_indexed, index)
  xpath = "//RunInfoRead[@IsIndexedRead=\"#{is_indexed}\"][#{index}]/@NumCycles"
  return index == 1 ? xpath : "sum(#{xpath})"
end