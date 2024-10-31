require 'date'

def validate_genome(genome)
  valid_inputs = ["hg19", "hg38", "mm9", "mm10"]

  unless valid_inputs.include?(genome)
    raise_message("Invalid genome name: #{genome}. " \
          "Acceptable values are: hg19, hg38, mm9, or mm10.")
  end
end

def parse_run_date(date)
  year = date.year.to_s[-2..] # last two digits of the year
  month = date.month.to_s
  day = date.day.to_s
  "#{year}-#{month}-#{day}T00:00:00"
end

def parse_instrument_model(instrument)
  match = /(\w+Seq)/.match(instrument)
  
  unless match
    raise_message("Could not parse Instrument_Model for #{subset['Name']}")
  end
  
  match[0]
end

def get_prop(set, prop)
	# If the set contains more than one unique value, raise an error
  if set.size > 1
    if prop == 'Donor'
      return nil
    else
      raise_message("Found Lane_Subset(s) with absent or unequal #{prop}")
    end
  end

  # Return the single unique value, or nil if there were no values
  set.first
end