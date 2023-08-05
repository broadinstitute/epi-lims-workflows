def find_xml_value(key, xml)
    i1 = xml.index('<' + key + '>')
    i2 = xml.index('</' + key + '>')
    if i1 and i2
        return xml[(i1 + key.length + 2)..(i2 - 1)]
    end
end

def parse_run_date(run_date)
    year = '20' + run_date[0..1]
    month = run_date[2..3]
    day = run_date[4..6]
    return [month, day, year].join('/');
end
  
def parse_run_parameters(run_parameters_file, sequencing_technology)
    xml = File.read(run_parameters_file.path)
    is_chip = sequencing_technology == 'ChIP'
    run_params = {
        folder_name: find_xml_value('RunId', xml),
        experiment_name: find_xml_value('ExperimentName', xml),
        instrument_model: 'NextSeq',
        max_mismatches: is_chip ? 1 : 2,
        min_mismatch_delta: is_chip ? 1 : 2,
        run_date: parse_run_date(find_xml_value('RunStartDate', xml))
    }
    if sequencing_technology != 'SHARE-Seq'
        run_params['read1'] = find_xml_value('Read1', xml)
        run_params['read2'] = find_xml_value('Read2', xml)
        run_params['index_read1'] = find_xml_value('Index1Read', xml)
        run_params['index_read2'] = find_xml_value('Index2Read', xml)
    end
    return run_params
end

def get_read_structure(seq_technology, read1, read2, index_read1, index_read2)
    read_structure = [
        "#{read1}T",
        '8B',
        (index_read1 > 8 ? ["#{index_read1 - 8}S"] : []).flatten,
        (index_read2 >= 8 ? ['8B'] : []).flatten,
        (index_read2 > 8 ? ["#{index_read2 - 8}S"] : []).flatten,
    ]
    if seq_technology == 'ChIP'
        return [
            read_structure.flatten,
            (read2 ? ["#{read2}T"] : []).flatten
        ].join(' ')
    end
    # TODO Mint-ChIP
    # if read2 <= 8
    #     throw Error('Read2 must be > 8')
    # end
    return [read_structure.flatten, '8B', "#{read2 - 8}T"].join(' ')
end

def reverse_complement(barcode)
    bases = {
      A: 'T',
      T: 'A',
      C: 'G',
      G: 'C',
      N: 'N',
    }
    return barcode
      .split('')
      .reverse()
      .map{ |base| bases[base] }
      .join('')
end

def get_multiplex_params(copa, seq_technology, instrument_model)
    library = copa
        .get_value('Pool Component')
        .get_value('Library')
    molecular_barcode = library
        .get_value('Molecular Barcode')
        .get_value('Molecular Barcode Sequence')
    if seq_technology == 'Mint-ChIP'
        molecular_index_sequence = library
            .get_value('ChrPrp')
            .get_value('ChrPrp Index')
            .get_value('Molecular Index Sequence')
    else
        molecular_index_sequence = ''
    end
    barcodes = [
        molecular_barcode,
        molecular_index_sequence
    ]
    if instrument_model == 'NextSeq' &&
        ((barcodes.length() == 2 && seq_technology == 'ChIP') || barcodes.length() == 3)
        barcodes[1] = reverse_complement(barcodes[1])
    end
    return barcodes.map{ |b| [copa.name, b] }
end

def get_candidate_molecular_indices()
    molecular_indexes = find_subjects(query:search_query(from:'ChrPrp Index') { |qb|
        qb.compare('ChrPrp Index In-Use', :eq, 'TRUE')
    })
    candidates = {}
    molecular_indexes.each{ |mi| candidates[mi.name] = mi.get_value('Molecular Index Sequence') }
    return candidates
end

def get_candidate_molecular_barcodes(sequencing_schema)
    # TODO in the case of NextSeq and when there is more than one barcode sequence
    # for each molecular barcode, we need to take the reverse complement of the
    # second barcode. See getWorkflowCandidateMolecularBarcodes in firebase api code
    molecular_barcodes = find_subjects(query:search_query(from:'Molecular Barcode') { |qb|
        qb.compare('Sequencing Schema', :eq, sequencing_schema)
    })
    candidates = {}
    molecular_barcodes.each{ |mb| candidates[mb.name] = mb.get_value('Molecular Barcode Sequence') }
    return candidates
end
