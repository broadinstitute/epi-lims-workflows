version development

struct PipelineInputs {
	Array[Int] lanes

	# Parameters for multiplexing, in the format:
	# [[library_name, barcode_1]]
	# Example:
	# [
	#   ["IDT8_i5_19", "AACCTTGG"],
	#   ["IDT8_i5_10", "GGTTCCAA"]
	# ]
	Array[Array[String]] multiplexParams

	# Barcodes used in each round:
	# [[[barcode_1, barcode_2, ...]]]
	# Example:
	# [
	#	  [
	#     ["SS V1 RIGHT HALF", "AACCTTGG", "AAAATTTT", "ACTGACTG"],
	#     ["SS V1 LEFT HALF", "GGTTCCAA", "GGGGCCCC", "CAGTCAGT"]	
	#   ],
	#	  [
	#     ["SS V2 RIGHT HALF", "AAAATTTT", "AACCTTGG", "ACTGACTG"],
	#     ["SS V2 LEFT HALF", "CAGTCAGT", "GGGGCCCC", "GGTTCCAA"]	
	#   ],
	# ]
	Array[Array[Array[String]]] round1Barcodes
	Array[Array[Array[String]]] round2Barcodes
	Array[Array[Array[String]]] round3Barcodes

	Array[String] ssCopas
	Array[String] pkrIds
	Array[String] sampleTypes
	Array[String] genomes
	# String genome

	# GCS file in which to store the output JSON
	String outputJson

	# optional context to pass down
	# in workflow outputs
	String? context
}

struct Copa {
	String name
	String pkrId
	String library
	String barcodeSequence
	String genome
	File round1
	File round2
	File round3
	String sampleType
}

struct Fastq {
	String pkrId
	String library
	String R1
	String sampleType
	String genome
	String notes
	Array[String] read1
	Array[String] read2
	Array[String] whitelist
}

struct LibraryOutput {
	String name
	# Float percentPfClusters
	# # Int meanClustersPerTile
	# Float pfBases
	# Float pfFragments
	String read1
	String read2
}

struct LaneOutput {
	Int lane
	Array[LibraryOutput] libraryOutputs
	String barcodeMetrics
	# File basecallMetrics
}

struct PipelineOutputs {
	String workflowType
	Array[LaneOutput] laneOutputs
	# Float meanReadLength
	# Float mPfFragmentsPerLane
	# Int maxMismatches
	# Int minMismatchDelta
	Int runId
	Int r1Length
	Int r2Length
	String flowcellId
	String instrumentId
	String runDate
	# String picardVersion
	String? context
}

#TODO
# lib barcode -> Group map (x)
# lib barcode + subset -> Copa name map ()

workflow SSBclToFastq {
	# input {
	# 	# Preprocess inputs
	# 	File bcl
	# 	Boolean zipped = true
	# 	Array[Int]? lanes
	# 	File metaCsv
	# 	String terra_project # set to none or make optional
	# 	String workspace_name
	# 	String dockerImage = "nchernia/share_task_preprocess:18"
	# }
	input {
		# .tar of the BCL folder
		File bcl
		Boolean zipped = true

		# GCS folder where to store the output data
		String outputDir

		# Read structure, e.g. 25T8B1S8B25T
		# String readStructure

		# Broad Institute
		# String sequencingCenter = "BI"

		# Pipelines to be processed independently
		Array[PipelineInputs] pipelines

		# Molecular barcodes to infer, in the format:
		# { "barcode_name": "barcode_sequence" }
		# Example:
		# {
		#   "tagged_1": "AACCTTGGAAAATTTT",
		#   "tagged_2": "GGTTCCAAGGGGCCCC"
		# }
		Map[String, String] candidateMolecularBarcodes

		# Mint barcodes to infer, in the format:
		# { "barcode_name": "barcode_sequence" }
		# Example:
		# {
		#   "CBE123": "ACTGACTG",
		#   "CBE456": "CAGTCAGT"
		# }
		Map[String, String] candidateMolecularIndices

		# URI of the Docker image with analysis tools
		String dockerImage = "us.gcr.io/buenrostro-share-seq/share_task_preprocess"
	}

	String barcodeStructure = "99M8B"
	String sequencingCenter = "BI"
	String tar_flags = if zipped then 'xzf' else 'xf'
	String untarBcl =
		'gsutil -m -o GSUtil:parallel_thread_count=1' +
		' -o GSUtil:sliced_object_download_max_components=8' +
		' cp "~{bcl}" . && ' +
		'tar "~{tar_flags}" "~{basename(bcl)}" --exclude Images --exclude Thumbnail_Images' 
	
	String getSampleSheet =
		'gsutil -m -o GSUtil:parallel_thread_count=1' +
		' -o GSUtil:sliced_object_download_max_components=8' +
		' cp "~{bcl}" . && ' +
		'tar "~{tar_flags}" "~{basename(bcl)}" SampleSheet.csv'

	# call BarcodeMap { # OPTIONAL
	# 	input:
	# 		metaCsv = metaCsv,
	# }


	# Int lengthLanes = length(select_first([lanes, GetLanes.lanes]))
	# # memory estimate for BasecallsToBam depends on estimated size of one lane of data
	# Float bclSize = size(bcl, 'G')
	# Float memory = ceil(1.4 * bclSize + 147) / lengthLanes
	# Float memory2 = (ceil(0.8 * bclSize) * 1.25) / lengthLanes # an unusual increase from 0.25 x for black swan
	
	scatter (p in pipelines) {
		if (length(p.lanes) == 0){
			call GetLanes {
				input: 
					bcl = bcl, 
					untarBcl = getSampleSheet
			}
		}
		Array[Int] lanes = select_first([GetLanes.lanes, p.lanes])
		Int lengthLanes = length(lanes)#select_first([lanes, GetLanes.lanes]))
		# memory estimate for BasecallsToBam depends on estimated size of one lane of data
		Float bclSize = size(bcl, 'G')
		Float memory = ceil(1.4 * bclSize + 147) / lengthLanes
		Float memory2 = (ceil(0.8 * bclSize) * 1.25) / lengthLanes # an unusual increase from 0.25 x for black swan
		
		scatter(i in range(length(p.pkrIds))){
			# TODO: migrate reverse complementing to the after script
			call make_tsv as round1 {
				input:
					barcodes = p.round1Barcodes[i]
			}
			call make_tsv as round2 {
				input:
					barcodes = p.round2Barcodes[i]
			}
			call make_tsv as round3 {
				input:
					barcodes = p.round3Barcodes[i]
			}
			call rev_comp {
				input: 
					name = p.multiplexParams[i][0],
					seq = p.multiplexParams[i][1]
			}
			Copa copa_map = object {
				name: p.ssCopas[i],
				pkrId: p.pkrIds[i],
				library: rev_comp.id,
				barcodeSequence: rev_comp.out,
				genome: p.genomes[i],
				round1: round1.tsv,
				round2: round2.tsv,
				round3: round3.tsv,
				sampleType: p.sampleTypes[i]
			}

			String uid = p.ssCopas[i]
		}

		call make_tsv as multiplexParams {
			input:
				barcodes = p.multiplexParams
		}

		call make_map as libraryBarcodes {
			input:
				tsv = multiplexParams.tsv
		}

		Map[String, Copa] map = as_map(zip(uid, copa_map))

		scatter (lane in lanes) {
			call ExtractBarcodes {
				input:
					bcl = bcl,
					untarBcl = untarBcl,
					libraryBarcodes = libraryBarcodes.map,
					barcodeStructure = barcodeStructure,
					lane = lane,
					dockerImage = dockerImage,
					memory = memory2
			}

			call BasecallsToBams {
				input:
					bcl = bcl,
					untarBcl = untarBcl,
					barcodes = ExtractBarcodes.barcodes,
					libraryBarcodes = libraryBarcodes.map,
					readStructure = ExtractBarcodes.readStructure,
					lane = lane,
					sequencingCenter = sequencingCenter,
					dockerImage = dockerImage,
					memory = memory
			}

			scatter(bam in BasecallsToBams.bams){
				# Convert unmapped, library-separated bams to fastqs
				# will assign cell barcode to read name 
				# assigns UMI for RNA to read name and adapter trims for ATAC
				# call BamLookUp { # OPTIONAL
				# 	input:
				# 		bam = basename(bam),
				# 		metaCsv = metaCsv,
				# }

				call getLibraryName {
					input:
						bam = basename(bam),
				}
			}

			Map[String, File] lib_map = as_map(zip(getLibraryName.library, BasecallsToBams.bams))

			scatter(copa in copa_map){
				File bam = lib_map[copa.library]
				call BamToRawFastq { 
					input: 
						bam = bam,
						pkrId = sub(copa.pkrId, ' ', '-'),
						library = copa.library,
						sampleType = sub(copa.sampleType, 'sc', ''),
						genome = copa.genome, 
						R1barcodeSet = copa.round1,
						R2barcodes = copa.round2,
						R3barcodes = copa.round3,
						dockerImage = dockerImage
				}

				call Transfer {
					input:
						name = sub(copa.name, ' ', '-'),
						read1 = BamToRawFastq.out.read1[0],
						read2 = BamToRawFastq.out.read2[0],
						whitelist = BamToRawFastq.out.whitelist[0]
				}

				LibraryOutput libraryOutput = object {
					name: copa.name,
					read1: Transfer.read1,
					read2: Transfer.read2
				}

				Fastq transferred = object {
					pkrId: BamToRawFastq.out.pkrId,
					library: BamToRawFastq.out.library,
					R1: BamToRawFastq.out.R1,
					sampleType: BamToRawFastq.out.sampleType,
					genome: BamToRawFastq.out.genome,
					notes: BamToRawFastq.out.notes,
					read1: [Transfer.read1],
					read2: [Transfer.read2],
					whitelist: [Transfer.whitelist]
				}

				call WriteTsvRow {
					input:
						fastq = transferred
				}
			}
			LaneOutput laneOutput = object {
				lane: lane,
				libraryOutputs: libraryOutput,
				barcodeMetrics: ExtractBarcodes.barcodeMetrics
			}
		}

		PipelineOutputs outputs = object {
			workflowType: 'share-seq-import',
			laneOutputs: laneOutput,
			r1Length: ExtractBarcodes.r1Length[0],
			r2Length: ExtractBarcodes.r2Length[0],
			# meanReadLength: BasecallMetrics.meanReadLength[0],
			# mPfFragmentsPerLane: AggregatePfFragments.mPfFragmentsPerLane,
			# maxMismatches: p.maxMismatches,
			# minMismatchDelta: p.minMismatchDelta,
			runId: BasecallsToBams.runId[0],
			flowcellId: BasecallsToBams.flowcellId[0],
			instrumentId: BasecallsToBams.instrumentId[0],
			runDate: BasecallsToBams.runDate[0],
			# picardVersion: GetVersion.picard,
			context: p.context,
		}

		call AggregateBarcodeQC {
			input:
				barcodeQCs = flatten(BamToRawFastq.R1barcodeQC)
		}

		call QC {
			input:
				barcodeMetrics = ExtractBarcodes.barcodeMetrics
		}
		
		call GatherOutputs {
			input:
				rows = flatten(WriteTsvRow.row),
				name =  if zipped then basename(bcl, ".tar.gz") else basename(bcl, ".tar"),
				dockerImage = dockerImage
		}
		
		call OutputJson {
			input:
				outputs = outputs,
				outputFile = p.outputJson,
		}
	}

	# call TerraUpsert { # OPTIONAL
	# 	input:
	# 		rna_tsv = GatherOutputs.rna_tsv,
	# 		rna_no_tsv = GatherOutputs.rna_no_tsv,
	# 		atac_tsv = GatherOutputs.atac_tsv,
	# 		run_tsv = GatherOutputs.run_tsv,
	# 		terra_project = terra_project,
	# 		workspace_name = workspace_name, 
	# 		dockerImage = dockerImage
	# } 

	# output {
	# 	Array[String] percentMismatch = QC.percentMismatch
	# 	Array[String] terraResponse = TerraUpsert.upsert_response
	# 	Array[File] monitoringLogsExtract = ExtractBarcodes.monitoringLog
	# 	Array[File] monitoringLogsBasecalls = BasecallsToBams.monitoringLog		
    #     File BarcodeQC = AggregateBarcodeQC.laneQC
	# 	# Array[Fastq] fastqs = flatten(BamToRawFastq.out)
	# 	# Array[Array[Array[File]]] fastqs = BamToRawFastq.fastqs
	# }
}

task make_map {
	input {
		File tsv
	}

	command <<<
	>>>

	output {
		Map[String, String] map = read_map(tsv)
	}

	runtime {
		docker: "ubuntu:latest"
	}
}

task make_tsv {
	input {
		Array[Array[String]] barcodes
	}

	File raw_tsv = write_tsv(barcodes)

	command <<<
		# Define a function to calculate the reverse complement of a DNA sequence
		reverse_complement() {
			local sequence="$1"
			local reversed_sequence=$(echo "$sequence" | rev)
			local complement=$(echo "$reversed_sequence" | tr 'ATCGatcg' 'TAGCtagc')
			echo "$complement"
		}

		# Input TSV file
		input_file=~{raw_tsv}

		# Output TSV file
		output_file="output.tsv"

		# Check if the input file exists
		if [ -e "$input_file" ]; then
			# Process each line in the input file
			while IFS=$'\t' read -r -a line; do
				name="${line[0]}"
				# Join the DNA sequences with tabs, skipping the first element
				dna_sequences=$(IFS=$'\t'; echo "${line[@]:1}")
				
				# Calculate the reverse complement for the DNA sequences
				reversed_dna_sequences=$(reverse_complement "$dna_sequences" | tr ' ' '\t')

				# Write the results to the output file and dedpulicate
				echo -e "$name\t$reversed_dna_sequences" >> "$output_file"
				sort -u "$output_file" -o "$output_file"

			done < "$input_file"
		else
			echo "Input file not found: $input_file"
			exit 1
		fi	
	>>>

	output {
		File tsv = "output.tsv"
	}

	runtime {
		docker: "ubuntu:latest"
	}
}

task rev_comp {
	input {
		String name
		String seq
	}

	command <<<
		echo ~{seq} | tr 'ATCGatcg' 'TAGCtagc' | rev
	>>>

	output {
		String id = name
		String out = read_string(stdout())
	}

	runtime {
		docker: "ubuntu:latest"
	}
}

task BarcodeMap {
	input {
		File metaCsv
		Int lane
	}

	command <<<
		if tail -n +5 ~{metaCsv} | head -1 | grep -q Lanes 
		then 		
			tail -n +6 ~{metaCsv} | awk -F "," -v num=~{lane} '{split($6,a," "); for(i in a) {if (a[i] == num) print $0}}' | cut -d, -f2 |  sed 's/ /\t/' > barcodes.tsv
		else
			tail -n +6 ~{metaCsv} | cut -d, -f2 |  sed 's/ /\t/' > barcodes.tsv
		fi
	>>>

	output {
		Map[String, String] out = read_map("barcodes.tsv")
	}

	runtime {
		docker: "ubuntu:latest"
	}
}

task GetLanes {
	input {
		File bcl
		String untarBcl
	}

	parameter_meta {
		bcl: {
			localization_optional: true
		}
	}
	
	Float bclSize = size(bcl, 'G')
	Int diskSize = ceil(2.1 * bclSize)
	String diskType = if diskSize > 375 then "SSD" else "LOCAL"
	# Float memory = ceil(5.4 * bclSize + 147) * 0.25
	String monitorLog = "get_lanes_monitor.log"

	command <<<
		set -e

		bash $(which monitor_script.sh) | tee ~{monitorLog} 1>&2 &

		~{untarBcl}
		tail -n+2 SampleSheet.csv | cut -d, -f2
	>>>

	output {
		Array[Int] lanes = read_lines(stdout())
		File monitorLog = monitorLog
	}

	runtime {
		docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:alpine"
		disks: "local-disk ~{diskSize} ~{diskType}"
		# memory: memory + 'G'
		# cpu: 14
	}
}

task ExtractBarcodes {
	input {
		# This function calls Picard to do library demultiplexing
		File bcl
		String untarBcl
		Map[String,String] libraryBarcodes
		String barcodeStructure 
		Int lane 
		String dockerImage
		Float memory
	}
	
	parameter_meta {
		bcl: {
			localization_optional: true
		}
	}

	File barcodesMap = write_map(libraryBarcodes)

	Int nBarcodes = 1
	String barcodeParamsFile = "barcode_params.tsv"
	String barcodeMetricsFile = "barcode_metrics.tsv"
	String basecallMetricsFile = "basecall_metrics.tsv"
	String parsedMetricsFile = "parsed_metrics.tsv"

	Float bclSize = size(bcl, 'G')

	Int diskSize = ceil(2.1 * bclSize)
	String diskType = if diskSize > 375 then "SSD" else "LOCAL"

	Int javaMemory = ceil((memory * 0.9) * 1000)

	String laneUntarBcl = untarBcl + ' RunInfo.xml RTAComplete.txt RunParameters.xml Data/Intensities/s.locs Data/Intensities/BaseCalls/L00~{lane}  && rm "~{basename(bcl)}"'
	
	String monitorLog = "extract_barcodes_monitor.log"

	command <<<
		set -e

		bash $(which monitor_script.sh) > ~{monitorLog} 2>&1 &

		~{laneUntarBcl}

		# append terminating line feed
		sed -i -e '$a\' ~{barcodesMap}

		read1Length=$(xmlstarlet sel -t -v "/RunInfo/Run/Reads/Read/@NumCycles" RunInfo.xml | head -n 1)
		echo ${read1Length} > r1Length.txt

		read2Length=$(xmlstarlet sel -t -v "/RunInfo/Run/Reads/Read/@NumCycles" RunInfo.xml | tail -n 1)
		echo ${read2Length} > r2Length.txt

		readStructure=${read1Length}T"~{barcodeStructure}"${read2Length}T
		echo ${readStructure} > readStructure.txt

		printf "barcode_name\tbarcode_sequence_1" | tee "~{barcodeParamsFile}"
		while read -r params; do	
			name=$(echo "${params}" | cut -d$'\t' -f1)
			barcodes=$(echo "${params}" | cut -d$'\t' -f2-)
			printf "\n%s\t%s" "${name}" "${barcodes}" | tee -a "~{barcodeParamsFile}"
		done < "~{barcodesMap}"

		# Extract barcodes, write to metrics file
		java -Xmx~{javaMemory}m -jar /software/picard.jar ExtractIlluminaBarcodes \
			-BASECALLS_DIR "Data/Intensities/BaseCalls" \
			-TMP_DIR . \
			-OUTPUT_DIR . \
			-BARCODE_FILE "~{barcodeParamsFile}" \
			-METRICS_FILE "~{barcodeMetricsFile}" \
			-READ_STRUCTURE "${readStructure}" \
			-LANE "~{lane}" \
			-NUM_PROCESSORS 0 \
			-COMPRESSION_LEVEL 1 \
			-GZIP true

		# collect basecall metrics
		java -Xmx~{javaMemory}m -jar /software/picard.jar CollectIlluminaBasecallingMetrics \
			-BASECALLS_DIR "Data/Intensities/BaseCalls" \
			-BARCODES_DIR . \
			-TMP_DIR . \
			-INPUT "~{barcodeParamsFile}" \
			-OUTPUT "~{basecallMetricsFile}" \
			-READ_STRUCTURE "${readStructure}" \
			-LANE "~{lane}"

		# parse read stats and basecall metrics
		python3 <<CODE
		import csv, re
		with  open('~{basecallMetricsFile}', 'r') as input, \
			open('~{parsedMetricsFile}', 'w') as output:
			fieldnames = (
				'name', 'percentPfClusters', 'meanClustersPerTile',
				'pfBases', 'pfFragments',
			)
			writer = csv.DictWriter(output,
				fieldnames=fieldnames, delimiter='\t', lineterminator='\n'
			)
			writer.writeheader()
			tsv = (row for row in input if not re.match('^(#.*|)$', row))
			for row in csv.DictReader(tsv, delimiter='\t'):
				name = row['MOLECULAR_BARCODE_NAME']
				if name:
				writer.writerow({
					'name': name,
					'percentPfClusters': round(
					float(row['PF_CLUSTERS']) / float(row['TOTAL_CLUSTERS']) * 100, 2
					),
					'meanClustersPerTile': row['MEAN_CLUSTERS_PER_TILE'],
					'pfBases': row['PF_BASES'],
					'pfFragments': round(float(row['PF_READS']) / reads_count, 2),
				})
		CODE
	>>>

	runtime {
		docker: dockerImage
		disks: "local-disk ~{diskSize} ~{diskType}"
		memory: memory + 'G'
		cpu: 4
	}

	output {
		Int r1Length = read_int("r1Length.txt")
		Int r2Length = read_int("r2Length.txt") 
		String readStructure = read_string("readStructure.txt")
		File barcodeMetrics = barcodeMetricsFile
		File basecallMetrics = basecallMetricsFile
		File parsedMetrics = parsedMetricsFile
		File barcodes = write_lines(glob("*_barcode.txt.gz"))
		File monitorLog = monitorLog
	}
}

task BasecallsToBams {
	input {
		# This function calls Picard to do library demultiplexing
		File bcl
		String untarBcl
		File barcodes
		Map[String,String] libraryBarcodes
		String readStructure 
		Int lane
		String sequencingCenter
		String dockerImage
		Float memory
	}

	parameter_meta {
		bcl: {
			localization_optional: true
		}
	}

	File barcodesMap = write_map(libraryBarcodes)
	String runIdFile = 'run_id.txt'
	String flowcellIdFile = 'flowcell_id.txt'
	String instrumentIdFile = 'instrument_id.txt'

	Float bclSize = size(bcl, 'G')

	Int diskSize = ceil(5 * bclSize)
	String diskType = if diskSize > 375 then "SSD" else "LOCAL"
	Int javaMemory = ceil((memory * 0.9) * 1000)
	String laneUntarBcl = untarBcl + ' RunInfo.xml RTAComplete.txt RunParameters.xml Data/Intensities/s.locs Data/Intensities/BaseCalls/L00~{lane}  && rm "~{basename(bcl)}"'
	String monitorLog = "basecalls_to_bams_monitor.log"

	command <<<
		set -e
		
		bash $(which monitor_script.sh) > ~{monitorLog} 2>&1 &

		~{laneUntarBcl}
		time gsutil -m cp -I . < "~{barcodes}"
		
		# append terminating line feed
		sed -i -e '$a\' ~{barcodesMap}

		# extract run parameters
		get_param () {
			param=$(xmlstarlet sel -t -v "/RunInfo/Run/$1" RunInfo.xml)
			echo "${param}" | tee "$2"
		}
		RUN_ID=$(get_param "@Number" "~{runIdFile}")
		FLOWCELL_ID=$(get_param "Flowcell" "~{flowcellIdFile}")
		INSTRUMENT_ID=$(get_param "Instrument" "~{instrumentIdFile}")

		parse_run_date () {
			run_date="$1"
			year="20${run_date:0:2}"
			month="${run_date:2:2}"
			day="${run_date:4:2}"
			echo "${month}/${day}/${year}"
		}
		runStartDate=$(xmlstarlet sel -t -v "/RunInfo/Run/@Id" RunInfo.xml | awk -F_ '{print $1}')
		parse_run_date $runStartDate > run_date.txt

		# prepare library parameter files
		LIBRARY_PARAMS="library_params.tsv"
		printf "SAMPLE_ALIAS\tLIBRARY_NAME\tOUTPUT\tBARCODE_1\n" | tee "${LIBRARY_PARAMS}"
		while read -r params; do	
			name=$(echo "${params}" | cut -d$'\t' -f1)
			barcodes=$(echo "${params}" | cut -d$'\t' -f2-)
			printf "\n%s\t%s\t%s_L%d.bam\t%s" \
				"${name}" "${name}" "${name// /_}" "~{lane}" "${barcodes}" \
				| tee -a "${LIBRARY_PARAMS}"
		done < "~{barcodesMap}"
		# generate BAMs
		java -Xmx~{javaMemory}m -jar /software/picard.jar IlluminaBasecallsToSam \
			BASECALLS_DIR="Data/Intensities/BaseCalls" \
			BARCODES_DIR=. \
			TMP_DIR=. \
			LIBRARY_PARAMS="${LIBRARY_PARAMS}" \
			IGNORE_UNEXPECTED_BARCODES=true \
			INCLUDE_NON_PF_READS=false \
			READ_STRUCTURE="~{readStructure}" \
			LANE="~{lane}" \
			RUN_BARCODE="${INSTRUMENT_ID}:${RUN_ID}:${FLOWCELL_ID}" \
			SEQUENCING_CENTER="~{sequencingCenter}" \
			NUM_PROCESSORS=0 \
			MAX_RECORDS_IN_RAM=5000000 
	>>>

	runtime {
		docker: dockerImage
		disks: "local-disk ~{diskSize} ~{diskType}"
		memory: memory + 'G'
		cpu: 14
		maxRetries: 3
	}

	output {
		Array[File] bams = glob("*.bam")
		Int runId = read_int("~{runIdFile}")
		String flowcellId = read_string("~{flowcellIdFile}")
		String instrumentId = read_string("~{instrumentIdFile}")
		String runDate = read_string("run_date.txt")
		File monitorLog = monitorLog
	}
}

# task BamLookUp {
# 	# Find pkrId, sampleType, and barcodeSets from CSV
# 	# Rigid assumption about order of columns in CSV
# 	input {
# 		String bam
# 		File metaCsv
# 	}

# 	command <<<
# 		bucket="gs://broad-buenrostro-bcl-outputs/"
# 		file=~{bam}
# 		lib="${file%_*} "
# 		grep -w $lib ~{metaCsv} | cut -d, -f1 | sed 's/ /-/' > pkrId.txt
# 		echo ${file%_*} > library.txt
# 		barcode1=$(grep -w $lib ~{metaCsv} | cut -d, -f3)
# 		echo ${bucket}${barcode1}.txt > R1barcodeSet.txt
# 		grep -w $lib ~{metaCsv} | cut -d, -f4 > sampleType.txt
# 		grep -w $lib ~{metaCsv} | cut -d, -f5 > genome.txt
# 		grep -w $lib ~{metaCsv} | cut -d, -f6 > notes.txt
# 	>>>

# 	output {
# 		String pkrId = read_string("pkrId.txt")
# 		String library = read_string("library.txt")
# 		String R1barcodeSet = read_string("R1barcodeSet.txt")
# 		String sampleType = read_string("sampleType.txt")
# 		String genome = read_string("genome.txt")
# 		String notes = read_string("notes.txt")
# 	}

# 	runtime {
# 		docker: "ubuntu:latest"
# 	}
# }

task getLibraryName {
	input {
		String bam
	}

	command <<<
		file="~{bam}"
		echo "${file%_*}" > library.txt
	>>>

	output {
		String library = read_string("library.txt")
	}

	runtime {
		docker: "ubuntu:latest"
	}
}


task BamToRawFastq {
	# Convert unmapped, library-separated bams to raw (uncorrected) FASTQs
	# assigns UMI for RNA to read name and adapter trims for ATAC

	# Defaults to file R1.txt in the src/python directory if no round barcodes given
	input {
		File bam
		String pkrId
		String library
		String sampleType
		String genome
		String notes = ''
		File R1barcodeSet
		File? R2barcodes
		File? R3barcodes
		String dockerImage
		Float? diskFactor = 5
		Float? memory = 8
	}

	String monitorLog = "bam_to_raw_fastq_monitor.log"
	String prefix = basename(bam, ".bam")
	
	Float bamSize = size(bam, 'G')
	Int diskSize = ceil(diskFactor * bamSize)
	String diskType = if diskSize > 375 then "SSD" else "LOCAL"

	command <<<
		set -e
		
		bash $(which monitor_script.sh) | tee ~{monitorLog} 1>&2 &

		# Create raw FASTQs from unaligned bam
		python3 /software/bam_to_raw_fastq.py \
			"~{bam}" \
			~{pkrId} \
			"~{prefix}" \
			~{R1barcodeSet} \
			~{if defined(R2barcodes) then "--r2_barcode_file ~{R2barcodes}" else ""} \
			~{if defined(R3barcodes) then "--r3_barcode_file ~{R3barcodes}" else ""}

		gzip *.fastq
	>>>

	output {
		Fastq out = object {
			pkrId: pkrId,
			library: library,
			R1: R1barcodeSet,
			sampleType: sampleType,
			genome: genome,
			notes: notes,
			read1: glob("*R1.fastq.gz"),
			read2: glob("*R2.fastq.gz"),
			whitelist: glob("*whitelist.txt")
		}
		File R1barcodeQC = "~{prefix}_R1_barcode_qc.txt"
		File monitorLog = monitorLog
	}
	runtime {
		docker: dockerImage
		disks: "local-disk ~{diskSize} ~{diskType}"
		memory: memory + 'G'
	}
}

task AggregateBarcodeQC {
	input {
		Array[File] barcodeQCs
	}

	command <<<
		echo -e "library\texact_match\tmismatch\tleft_shift\tright_shift\tnonmatch\tpoly_G_barcode" > R1_barcode_stats.txt
		cat "~{sep='" "' barcodeQCs}" >> R1_barcode_stats.txt
	>>>
	
	output {
		File laneQC = 'R1_barcode_stats.txt'
	}
	
	runtime {
		docker: "ubuntu:latest"
	}
}

task QC {
	input {
		Array[File] barcodeMetrics
	}

	Int total = length(barcodeMetrics)
	
	command <<<
		ARRAY=(~{sep=" " barcodeMetrics}) # Load array into bash variable
		for (( c = 0; c < ~{total}; c++ )) # bash array are 0-indexed ;)
		do
			awk '$1=="NNNNNNNN"' ${ARRAY[$c]} | cut -f11
		done
	>>>
	
	output {
		Array[String] percentMismatch = read_lines(stdout())
	}
	
	runtime {
		docker: "ubuntu:latest"
	}
}

task Transfer {
	input {
		String name
		File read1
		File read2
		File whitelist
		String bucket = "gs://broad-epi-ss-lane-subsets"
	}

	Int diskSize = ceil(size([read1, read2], 'G') * 2.2 + 1)
	String diskType = if diskSize > 375 then "SSD" else "LOCAL"

	command <<<
		IFS="_" read -ra fields <<< "~{basename(read1)}"
		library="${fields[0]}"
		lane="${fields[1]}"
		pkr="${fields[2]}"
		r1="${fields[3]}"

		dest_r1="~{bucket}"/~{name}_${lane}_${pkr}_${r1}_R1.fastq.gz
		dest_r2="~{bucket}"/~{name}_${lane}_${pkr}_${r1}_R2.fastq.gz
		dest_wl="~{bucket}"/~{name}_whitelist.txt

		gsutil cp "~{read1}" ${dest_r1}
		gsutil cp "~{read2}" ${dest_r2}
		gsutil cp "~{whitelist}" ${dest_wl}

		echo "${dest_r1}" > read1.txt
		echo "${dest_r2}" > read2.txt
		echo "${dest_wl}" > whitelist.txt
	>>>

	output {
		String read1 = read_string("read1.txt")
		String read2 = read_string("read2.txt")
		String whitelist = read_string("whitelist.txt")	
	}

	runtime {
		docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:alpine"
		disks: "local-disk ~{diskSize} ~{diskType}"
	}
}

task OutputJson {
	input {
		PipelineOutputs outputs
		String outputFile
	}

	command <<<
		gsutil cp "~{write_json(outputs)}" "~{outputFile}"
	>>>

	runtime {
		docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:alpine"
	}
}

task WriteTsvRow {
	input {
		Fastq fastq
	}
	Array[String] read1 = fastq.read1
	Array[String] read2 = fastq.read2
	Array[String] whitelist = fastq.whitelist

	command <<<
		# echo -e "Library\tPKR\tR1_subset\tType\tWhitelist\tfastq_R1\tfastq_R2\tGenome\tNotes" > fastq.tsv
		echo -e "~{fastq.library}\t~{fastq.pkrId}\t~{fastq.R1}\t~{fastq.sampleType}\t~{sep=',' whitelist}\t~{sep=',' read1}\t~{sep=',' read2}\t~{fastq.genome}\t~{fastq.notes}" > row.tsv
	>>>

	output {
		File row = 'row.tsv'
	}

	runtime {
		docker: "ubuntu:latest"
	}
}

task GatherOutputs {
	input {
		Array[File] rows
		String name
		String dockerImage
	}

	command <<<
		echo -e "Library\tPKR\tR1_subset\tType\tWhitelist\tRaw_FASTQ_R1\tRaw_FASTQ_R2\tGenome\tNotes" > fastq.tsv
		cat ~{sep=' ' rows} >> fastq.tsv

		echo "test,test" > test.csv

		python3 /software/write_terra_tables.py --input 'fastq.tsv' --name ~{name} --meta test.csv	>>>

	runtime {
		docker: dockerImage
	}
	output {
		File rna_tsv = "rna.tsv"
		File rna_no_tsv = "rna_no.tsv"
		File atac_tsv = "atac.tsv"
		File run_tsv = "run.tsv"
	}
}

task TerraUpsert {
	input {
		File rna_tsv
		File rna_no_tsv
		File atac_tsv
		File run_tsv
		String terra_project
		String workspace_name
		String dockerImage
	}
	
	command <<<
		set -e
		python3 /software/flexible_import_entities_standard.py \
			-t "~{rna_tsv}" \
			-p "~{terra_project}" \
			-w "~{workspace_name}"
		
		python3 /software/flexible_import_entities_standard.py \
			-t "~{rna_no_tsv}" \
			-p "~{terra_project}" \
			-w "~{workspace_name}"

		python3 /software/flexible_import_entities_standard.py \
			-t "~{atac_tsv}" \
			-p "~{terra_project}" \
			-w "~{workspace_name}"

		python3 /software/flexible_import_entities_standard.py \
			-t "~{run_tsv}" \
			-p "~{terra_project}" \
			-w "~{workspace_name}"
	>>>
	
	runtime {
		docker: dockerImage
		memory: "2 GB"
		cpu: 1
	}
	
	output {
		Array[String] upsert_response = read_lines(stdout())
	}
}