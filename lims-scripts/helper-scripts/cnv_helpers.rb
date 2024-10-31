require 'set'

def wce_sort_fn(a, b)
  a[:updated_at] == b[:updated_at] ? a[:id] - b[:id] : (a[:updated_at] <= b[:updated_at] ? -1 : 1)
end

def get_library(alignment)
  return alignment
    .get_value('Lane Subset')
    .get_value('Component of Pooled SeqReq')
    .get_value('CoPA')
    .get_value('Pool Component')
    .get_value('Library')
end

def get_biosam(library)
  if library.name.include? 'Mint'
    return library
      .get_value('In Vitro Transcript')
      .get_value('Mint-ChIP')
      .get_value('CoMoChrPrp')
      .get_value('Chromatin Prep')
      .get_value('BioSAli')
      .get_value('Biological Sample')
  end
  return library
    .get_value('ChIP')
    .get_value('Chromatin Prep')
    .get_value('BioSAli')
    .get_value('Biological Sample')
  # TODO case for neither?
end

def get_alignments(library, biosam)
  if library.name.include? 'Mint'
    alignments = find_subjects(query:search_query(from:'Alignment') { |al|
      al.compare('"Lane Subset"->"Component of Pooled SeqReq"->' +
        '"CoPA"->"Pool Component"->"Library"["Mint_DNA_Lib"]->' +
        '"In Vitro Transcript"->"Mint-ChIP"->"CoMoChrPrp"->' +
        '"Chromatin Prep"->"BioSAli"->"Biological Sample"->name', :eq, biosam)
    }, limit:30000)
  else
    alignments = find_subjects(query:search_query(from:'Alignment') { |al|
      al.compare('"Lane Subset"->"Component of Pooled SeqReq"->' +
        '"CoPA"->"Pool Component"->"Library"["DNA_Lib"]->"ChIP"->' +
        '"Chromatin Prep"->"BioSAli"->"Biological Sample"->name', :eq, biosam)
    }, limit:30000)
  end
  return alignments
end

# TODO for some reason find_subjects complains the results
# are too large without a limit parameter, even though
# there are only ~3k results at time of comment
def get_wces(ref_seq, library, biosam)
  # TODO Could be precomputed to save time
  wce_apps = find_subjects(query:search_query(from:'Alignment Post Processing') { |app|
    app.and(
      app.compare('Epitopes', :eq, 'WCE'),
      app.compare('Reference Sequence', :eq, ref_seq)
    )
  }, limit:30000)

  # TODO could be precomputed to save time
  wce_alignments = Set[]
  wce_alignment_to_app = {}
  wce_apps.each do |app|
    app['Input_Alignments_SL'].each do |al|
      wce_alignments.add(al)
      if wce_alignment_to_app.include?(al.name)
        wce_alignment_to_app[al.name].add(app)
      else
        wce_alignment_to_app[al.name] = Set[app]
      end
    end
  end
  
  # This is a way to efficiently get WCE Apps by finding
  # the intersection of wce alignments and alignments
  # associated with the current biosam. Otherwise requires
  # traveling from alignment to biosam for each alignment,
  # which is very inefficient in lims
  alignments = get_alignments(library, biosam)
    .to_set
    .intersection(wce_alignments)

  # Get corresponding APPs
  apps = []
  alignments
    .map{ |a| wce_alignment_to_app[a.name] }
    .each do |app_set|
      app_set.each{ |app| apps.push(app) }
    end

  return apps
end