def get_prop(subjects, subject_type, prop)
  values = subjects.map { |s| s[prop] }.compact
  if values.uniq.length > 1
    raise_message("Error: Found #{subject_type}(s) with unequal #{prop}")
  end
  values.first
end

def check_missing_props(subjects, prop)
  error_names = subjects.select do |s|
    value = s[prop]
    value.nil? || (value.is_a?(Array) && value.empty?)
  end.map(&:name).join(', ')

  unless error_names.empty?
    raise_message("Missing #{prop} from #{error_names}")
  end
end

def reverse_complement(barcode)
  bases = {
    'A' => 'T',
    'T' => 'A',
    'C' => 'G',
    'G' => 'C',
    'N' => 'N',
  }
  return barcode
    .split('')
    .reverse
    .map { |base| bases[base] }
    .join('')
end
  
def get_default_genome(species_common_name)
  case species_common_name
  when 'Human'
    'hg19'
  when 'House mouse'
    'mm10'
  else
    ''
  end
end

def get_multiplex_params(copa, seq_technology, instrument_model)
  library = copa
    .get_value('Pool Component')
    .get_value('Library')
  molecular_barcode = library.get_value('Molecular Barcode') || 
                      library.get_value('MoMint_DNA_Lib')
                             .get_value('Molecular Barcode')
  barcodes = molecular_barcode.get_value('Molecular Barcode Sequence').split('_')
  if seq_technology == 'Mint-ChIP'
    molecular_index_sequence = library
      .get_value('In Vitro Transcript')
      .get_value('Mint-ChIP')
      .get_value('CoMoChrPrp')
      .get_value('Chromatin Prep')
      .get_value('ChrPrp Index')
      .get_value('Molecular Index Sequence')
    barcodes.push(molecular_index_sequence)
  end
  if instrument_model == 'NextSeq' &&
    ((barcodes.length == 2 && seq_technology == 'ChIP') || barcodes.length == 3)
    barcodes[1] = reverse_complement(barcodes[1])
  end
  return [copa.name, *barcodes]
end

def get_projects(copa)
  library = copa.get_value('Pool Component')
                .get_value('Library')
  pre_chr_prep = library.get_value('ChIP') || 
                 library.get_value('In Vitro Transcript')
                        .get_value('Mint-ChIP')
                        .get_value('CoMoChrPrp')
  project = pre_chr_prep.get_value('Chromatin Prep')
                        .get_value('BioSAli')
                        .get_value('Biological Sample')
                        .get_value('Project')
  return [copa.name, [*project.name]]
end

def get_candidate_molecular_indices()
  molecular_indexes = find_subjects(
    query:search_query(from:'ChrPrp Index') do |qb|
      qb.compare('ChrPrp Index In-Use', :eq, 'TRUE')
    end
  )
  candidates = {}
  molecular_indexes.each do |mi| 
    candidates[mi.name] = mi.get_value('Molecular Index Sequence')
  end
  candidates
end

def get_candidate_molecular_barcodes(sequencing_schema, instrument_model)
  molecular_barcodes = find_subjects(
    query:search_query(from:'Molecular Barcode') do |qb|
      qb.compare('Sequencing Schema', :eq, sequencing_schema)
    end
  )
  candidates = {}
  molecular_barcodes.each do |mb| 
    barcodes = mb.get_value('Molecular Barcode Sequence').split('_')
    if instrument_model == 'NextSeq' && barcodes.length == 2
      barcodes[1] = reverse_complement(barcodes[1])
    end
    candidates[mb.name] = barcodes.join('')
  end
  return candidates
end