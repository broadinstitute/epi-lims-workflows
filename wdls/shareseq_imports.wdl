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
  Array[String] pkrId
  Array[String] sampleType
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
	String libraryBarcode
	String barcodeSequence
	File round1
	File round2
	File round3
	String type
}

struct Fastq {
	String pkrId
	String library
	String R1
	String sampleType
	String genome
	Array[String] read1
	Array[String] read2
}

struct LibraryOutput {
  String name
#   Float percentPfClusters
#   Int meanClustersPerTile
#   Float pfBases
#   Float pfFragments
  String read1
  String read2
}

struct LaneOutput {
  Int lane
  Array[LibraryOutput] libraryOutputs
  String barcodeMetrics
#   File basecallMetrics
}

struct PipelineOutputs {
  String workflowType
  Array[LaneOutput] laneOutputs
#   Float meanReadLength
#   Float mPfFragmentsPerLane
#   Int maxMismatches
#   Int minMismatchDelta
  Int runId
  String flowcellId
  String instrumentId
#   String picardVersion
  String? context
}

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
		String dockerImage = "nchernia/share_task_preprocess:18"
	}

	String barcodeStructure = "14S10M28S10M28S9M8B"
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
		
		scatter(i in range(length(p.pkrId))){
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
				pkrId: p.pkrId[i],
				libraryBarcode: rev_comp.id,
				barcodeSequence: rev_comp.out,
				round1: round1.tsv,
				round2: round2.tsv,
				round3: round3.tsv,
				type: p.sampleType[i]
			}

			String uid = p.multiplexParams[i][0]
		}

		Map[String, String] libraryBarcodes = as_map(zip(rev_comp.id, rev_comp.out))
		Map[String, Copa] map = as_map(zip(uid, copa_map))

		scatter (lane in lanes) {
			call ExtractBarcodes {
				input:
					bcl = bcl,
					untarBcl = untarBcl,
					libraryBarcodes = libraryBarcodes,
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
					libraryBarcodes = libraryBarcodes,
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

				Copa copa = map[getLibraryName.library]

				call BamToFastq { 
					input: 
						bam = bam,
						pkrId = copa.pkrId,
						library = copa.libraryBarcode,
						sampleType = sub(copa.type, 'sc', ''), 
						R1barcodeSet = copa.round1,
						R2barcodes = copa.round2,
						R3barcodes = copa.round3,
						dockerImage = dockerImage
				}

				LibraryOutput libraryOutput = object {
					name: copa.name,
					read1: BamToFastq.out.read1[0],
					read2: BamToFastq.out.read2[0]
				}

				# call WriteTsvRow {
				# 	input:
				# 		fastq = BamToFastq.out
				# }
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
			# meanReadLength: BasecallMetrics.meanReadLength[0],
			# mPfFragmentsPerLane: AggregatePfFragments.mPfFragmentsPerLane,
			# maxMismatches: p.maxMismatches,
			# minMismatchDelta: p.minMismatchDelta,
			runId: BasecallsToBams.runId[0],
			flowcellId: BasecallsToBams.flowcellId[0],
			instrumentId: BasecallsToBams.instrumentId[0],
			# picardVersion: GetVersion.picard,
			context: p.context,
		}

		call AggregateBarcodeQC {
			input:
				barcodeQCs = flatten(BamToFastq.qc)
		}

		call QC {
			input:
				barcodeMetrics = ExtractBarcodes.barcodeMetrics
		}

		call OutputJson {
			input:
				outputs = outputs,
				outputFile = p.outputJson,
		}
	}
	# call GatherOutputs { # OPTIONAL
	# 	input:
	# 		rows = flatten(WriteTsvRow.row),
	# 		name =  if zipped then basename(bcl, ".tar.gz") else basename(bcl, ".tar"),
	# 		metaCsv = metaCsv, 
	# 		dockerImage = dockerImage
	# }

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
	# 	# Array[Fastq] fastqs = flatten(BamToFastq.out)
	# 	# Array[Array[Array[File]]] fastqs = BamToFastq.fastqs
	# }
}

task make_map {
	input {
		Array[Array[String]] multiplexParams
	}

	command <<<
	>>>

	output {
		Map[String, String] libraryBarcodes = read_map(write_tsv(multiplexParams))
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

				# Write the results to the output file
				echo -e "$name\t$reversed_dna_sequences" >> "$output_file"
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
	}

	command <<<
		tail -n +6 ~{metaCsv} | cut -d, -f2 |  sed 's/ /\t/' > barcodes.tsv
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

	command <<<
		set -e

		~{untarBcl}
		tail -n+2 SampleSheet.csv | cut -d, -f2
	>>>

	output {
		Array[Int] lanes = read_lines(stdout())
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

	Float bclSize = size(bcl, 'G')

	Int diskSize = ceil(2.1 * bclSize)
	String diskType = if diskSize > 375 then "SSD" else "LOCAL"

	Int javaMemory = ceil((memory - 0.5) * 1000)

        String laneUntarBcl = untarBcl + ' RunInfo.xml RTAComplete.txt RunParameters.xml Data/Intensities/s.locs Data/Intensities/BaseCalls/L00~{lane}  && rm "~{basename(bcl)}"'
	command <<<
		set -e
		bash /software/monitor_script.sh > monitoring.log &
		~{laneUntarBcl}

		# append terminating line feed
		sed -i -e '$a\' ~{barcodesMap}

		readLength=$(xmlstarlet sel -t -v "/RunInfo/Run/Reads/Read/@NumCycles" RunInfo.xml | head -n 1)T
		readStructure=${readLength}"~{barcodeStructure}"${readLength}
		echo ${readStructure} > readStructure.txt

		printf "barcode_name\tbarcode_sequence1" | tee "~{barcodeParamsFile}"
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
	>>>

	runtime {
		docker: dockerImage
		disks: "local-disk ~{diskSize} ~{diskType}"
		memory: memory + 'G'
		cpu: 4
	}

	output {
		String readStructure = read_string("readStructure.txt")
		File barcodeMetrics = barcodeMetricsFile
		File barcodes = write_lines(glob("*_barcode.txt.gz"))
		File monitoringLog = "monitoring.log"
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
	Int javaMemory = ceil((memory - 0.5) * 1000)
        String laneUntarBcl = untarBcl + ' RunInfo.xml RTAComplete.txt RunParameters.xml Data/Intensities/s.locs Data/Intensities/BaseCalls/L00~{lane}  && rm "~{basename(bcl)}"'
	command <<<
		set -e
		bash /software/monitor_script.sh > monitoring.log &
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
        File monitoringLog = "monitoring.log"
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


task BamToFastq {
	# Convert unmapped, library-separated bams to fastqs
	# will assign cell barcode to read name 
	# assigns UMI for RNA to read name and adapter trims for ATAC

	# Defaults to file R1.txt in the src/python directory if no round barcodes given
	input {
		File bam
		String pkrId
		String library
		String sampleType
		String genome = 'hg38'
		# Array[Array[String]] R1barcodeSet
		# Array[Array[String]]? R2barcodes
		# Array[Array[String]]? R3barcodes
		File R1barcodeSet
		File? R2barcodes
		File? R3barcodes
		String dockerImage
	}

	String prefix = basename(bam, ".bam")
	
	Float bamSize = size(bam, 'G')

	Int diskSize = ceil(bamSize + 5)
	String diskType = if diskSize > 375 then "SSD" else "LOCAL"

	Float memory = ceil(1.5 * bamSize + 1) * 2


	# Workaround since write_tsv does not take type "?", must be defined
	# Array[Array[String]] R2_if_defined = select_first([R2barcodes, []])
	# Array[Array[String]] R3_if_defined = select_first([R3barcodes, []])

	# Use round 1 default barcode set in rounds 2 and 3 if not sent in
	File R1file = R1barcodeSet #write_tsv(R1barcodeSet)
	File R2file = if defined(R2barcodes)
					# then write_tsv(R2_if_defined) else R1file
					then R2barcodes else R1barcodeSet
	File R3file = if defined(R3barcodes)
					# then write_tsv(R3_if_defined) else R1file
					then R3barcodes else R1barcodeSet


	command <<<
		samtools addreplacerg -r '@RG\tID:~{pkrId}' "~{bam}" -o tmp.bam
		python3 /software/bam_fastq.py tmp.bam ~{R1file} ~{R2file} ~{R3file} -p "~{prefix}" -s ~{sampleType}

		gzip *.fastq
	>>>

	output {
		Fastq out = object {
			pkrId: pkrId,
			library: library,
			R1: R1barcodeSet,
			sampleType: sampleType,
			genome: genome,
			read1: glob("*R1.fastq.gz"),
			read2: glob("*R2.fastq.gz")
		}

		File qc = 'qc.txt'
		# Array[File] fastqs = glob("*.fastq")
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
		echo -e "LIB_BARCODE\tEXACT\tPASS\tFAIL_MISMATCH\tFAIL_HOMOPOLYMER\tFAIL_UMI" > final.txt
		cat ~{sep=" " barcodeQCs} >> final.txt
		# awk 'BEGIN{FS="\t"; OFS="\t"} {x+=$1; y+=$2; z+=$3} END {print x,y,z}' combined.txt > final.txt
	>>>
	
	output {
		File laneQC = 'final.txt'
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

# task WriteTsvRow {
# 	input {
# 		Fastq fastq
# 	}
# 	Float fastqSize = size(fastq.read1[0], 'G')
#         Int diskSize = ceil(2.2 * length(fastq.read1)*fastqSize)
#         String diskType = if diskSize > 375 then "SSD" else "LOCAL"
# 	Array[String] read1 = fastq.read1
# 	Array[String] read2 = fastq.read2

# 	command <<<
# 		# echo -e "Library\tPKR\tR1_subset\tType\tfastq_R1\tfastq_R2\tGenome\tNotes" > fastq.tsv
# 		echo -e "~{fastq.library}\t~{fastq.pkrId}\t~{fastq.R1}\t~{fastq.sampleType}\t~{sep=',' read1}\t~{sep=',' read2}\t~{fastq.genome}\t~{fastq.notes}" > row.tsv
# 	>>>

# 	output {
# 		File row = 'row.tsv'
# 	}

# 	runtime {
# 		docker: "ubuntu:latest"
# 		disks: "local-disk ~{diskSize} ~{diskType}"
# 	}
# }

# task GatherOutputs {
# 	input {
# 		Array[File] rows
# 		String name
# 		File metaCsv
# 		String dockerImage
# 	}

# 	command <<<
# 		echo -e "Library\tPKR\tR1_subset\tType\tfastq_R1\tfastq_R2\tGenome\tNotes" > fastq.tsv
# 		cat ~{sep=' ' rows} >> fastq.tsv

# 		python3 /software/write_terra_tables.py --input 'fastq.tsv' --name ~{name} --meta ~{metaCsv}
# 	>>>

# 	runtime {
# 		docker: dockerImage
# 	}
# 	output {
# 		File rna_tsv = "rna.tsv"
# 		File rna_no_tsv = "rna_no.tsv"
# 		File atac_tsv = "atac.tsv"
# 		File run_tsv = "run.tsv"
# 	}
# }

# task TerraUpsert {
# 	input {
# 		File rna_tsv
# 		File rna_no_tsv
# 		File atac_tsv
# 		File run_tsv
# 		String terra_project
# 		String workspace_name
# 		String dockerImage
# 	}
	
# 	command <<<
# 		set -e
# 		python3 /software/flexible_import_entities_standard.py \
# 			-t "~{rna_tsv}" \
# 			-p "~{terra_project}" \
# 			-w "~{workspace_name}"
		
# 		python3 /software/flexible_import_entities_standard.py \
# 			-t "~{rna_no_tsv}" \
# 			-p "~{terra_project}" \
# 			-w "~{workspace_name}"

# 		python3 /software/flexible_import_entities_standard.py \
# 			-t "~{atac_tsv}" \
# 			-p "~{terra_project}" \
# 			-w "~{workspace_name}"

# 		python3 /software/flexible_import_entities_standard.py \
# 			-t "~{run_tsv}" \
# 			-p "~{terra_project}" \
# 			-w "~{workspace_name}"
# 	>>>
	
# 	runtime {
# 		docker: dockerImage
# 		memory: "2 GB"
# 		cpu: 1
# 	}
	
# 	output {
# 		Array[String] upsert_response = read_lines(stdout())
# 	}
# }