require 'json'
require_script 'submit_jobs'

tracks = subjects.map{ |s| s.get_value('Track') }
apps = tracks.map{ |s| s.get_value('Alignment Post Processing') }

if tracks.compact.empty?
  raise_message("No tracks are present")
end

ref_seq = apps.first.get_value('Reference Sequence').name
match = /^(hg(19|38)|mm10)_/.match(ref_seq)

unless match
  raise_message("Could not parse a supported genome (hg19, hg38, mm10) from #{ref_seq} for #{tracks.first.name}")
end

genome_name = match[1]

unless apps.all? { |t| t.get_value('Reference Sequence').name.start_with?("#{genome_name}_") }
  raise_message("Viewing tracks with different genomes is not supported")
end

formatted_tracks = subjects.map do |s|
  track = s.get_value('Track')
  app = track.get_value('Alignment Post Processing')

  out = {
    :track => track.name,
    :library => app.get_value('Library by formula').name,
    :parent => s.name,
    :cellType => app['Cell Types'],
    :epitope => app['Epitopes'],
    :refSeq => app.get_value('Reference Sequence').name,
    :totalFrag => app['Total Fragments'],
    :alignedFrag => app['Aligned Fragments'],
    :dupFrag => app['Duplicate Fragments'],
    :perDupFrag => app['Percent Duplicate Fragments'],
    :bigwig => track['BigWig Filename URI']
  }

  out
end

req = {
    :workflow => 'ucsc',
    :subj_name => subjects.map{ |s| s.name }.join(','),
    :subj_id => subjects.map{ |s| s.id }.join(','),
    :genome => genome_name,
    :tracks => formatted_tracks,
}

Rails.logger.info("#{req.to_json}")

# show_message("#{req.to_json}")

submit_jobs(req, trackview: true)