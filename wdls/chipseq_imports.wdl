version 1.0

struct PipelineInputs {
  Array[Int] lanes

  # Parameters for multiplexing, in the format:
  # [[library_name, barcode_1, (barcode_2, ...)]]
  # Example:
  # [
  #   ["CoPA 12345", "AACCTTGG", "AAAATTTT", "ACTGACTG"],
  #   ["CoPA 54321", "GGTTCCAA", "GGGGCCCC", "CAGTCAGT"]
  # ]
  Array[Array[String]] multiplexParams

  # Barcode matching parameters for Picard
  Int maxMismatches
  Int minMismatchDelta

  # GCS file in which to store the output JSON
  String outputJson

  # optional context to pass down
  # in workflow outputs
  String? context
}

struct LibraryOutput {
  String name
  Float percentPfClusters
  Int meanClustersPerTile
  Float pfBases
  Float pfFragments
  String read1
  String? read2
}

struct LaneOutput {
  Int lane
  Array[LibraryOutput] libraryOutputs
  File barcodeMetrics
  File basecallMetrics
}

struct PipelineOutputs {
  Array[LaneOutput] laneOutputs
  Float meanReadLength
  Float mPfFragmentsPerLane
  Int maxMismatches
  Int minMismatchDelta
  Int runId
  String flowcellId
  String instrumentId
  String picardVersion
  String? context
}

workflow BclToFastq {
  input {
    # .tar of the BCL folder
    File bcl

    # GCS folder where to store the output data
    String outputDir

    # Read structure, e.g. 25T8B1S8B25T
    String readStructure

    # Broad Institute
    String sequencingCenter = "BI"

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
    String dockerImage
  }

  String untarBcl =
    'time gsutil -o GSUtil:parallel_thread_count=1' +
    ' -o GSUtil:sliced_object_download_max_components=8' +
    ' cp "~{bcl}" . && ' +
    'time tar xf "~{basename(bcl)}" --exclude Images --exclude Thumbnail_Images && ' +
    'rm "~{basename(bcl)}"'

  String cloudSdkImage = "gcr.io/google.com/cloudsdktool/cloud-sdk:alpine"
}

task GetVersion {
  input {
    String dockerImage
  }

  command <<<
    cat /opt/versions.tsv
  >>>

  runtime {
    docker: dockerImage
    disks: "local-disk 1 HDD"
    memory: "1G"
    cpu: 1
  }

  output {
    String picard = read_map(stdout())["picard"]
  }
}

task ExtractBarcodes {
  input {
    File bcl
    String untarBcl

    String readStructure
    Array[Array[String]] multiplexParams
    Map[String, String] candidateMolecularBarcodes
    Map[String, String] candidateMolecularIndices

    Int maxMismatches
    Int minMismatchDelta

    Int lane
    Int compressionLevel = 1

    String dockerImage
  }

  parameter_meta {
    bcl: {
      localization_optional: true
    }
  }

  File multiplexParamsFile = write_tsv(multiplexParams)
  String barcodeParamsFile = "barcode_params.tsv"
  String barcodeMetricsFile = "barcode_metrics.tsv"
  String barcodesInferredFile = "barcodes_inferred.tsv"

  Int nBarcodes = length(multiplexParams[0]) - 1

  Float bclSize = size(bcl, 'G')

  Int diskSize = ceil(1.9 * bclSize + 5)
  String diskType = if diskSize > 375 then "SSD" else "LOCAL"

  Float memory = ceil(0.8 * bclSize) * 2.25  # an unusual increase from 0.25 x for black swan
  Int javaMemory = ceil((memory * 0.9) * 1000)

  command <<<
    set -e

    ~{untarBcl}

    # prepare barcode parameter files
    printf "barcode_name" | tee "~{barcodeParamsFile}"
    for i in {1..~{nBarcodes}}; do
      printf "\tbarcode_sequence_%d" "$i" | tee -a "~{barcodeParamsFile}"
    done
    while read -r params; do
      printf "\n%s" "${params}" | tee -a "~{barcodeParamsFile}"
    done < "~{multiplexParamsFile}"

    n=$(grep -Eo '[[:alpha:]]+|[0-9]+' <<< "~{readStructure}" | grep -B 1 'B' | grep -v 'B' | awk '{sum+=$1} END {print sum}')
    barcodeN=$(for i in `seq $n`; do echo 'N';done | tr --delete '\n')

    # extract all barcodes from the sample,
    # whether they're in multiplexParams or not
    java -Xmx~{javaMemory}m -jar /opt/picard.jar ExtractIlluminaBarcodes \
      BASECALLS_DIR="Data/Intensities/BaseCalls" \
      TMP_DIR=. \
      OUTPUT_DIR=. \
      BARCODE="${barcodeN}" \
      METRICS_FILE="~{barcodeMetricsFile}" \
      READ_STRUCTURE="~{readStructure}" \
      LANE="~{lane}" \
      NUM_PROCESSORS=0 \
      COMPRESSION_LEVEL="~{compressionLevel}" \
      GZIP=true

    # match all barcodes to the list of candidates,
    # and fail if any barcodes from multiplexParams are low-yield
    /opt/infer_barcodes.py \
      "~{multiplexParamsFile}" \
      "~{write_map(candidateMolecularBarcodes)}" \
      "~{write_map(candidateMolecularIndices)}" \
      "~{barcodesInferredFile}" \
      "~{maxMismatches}" \
      "~{minMismatchDelta}"

    # finally, extract only the barcodes from multiplexParams
    rm ./*_barcode.txt.gz
    java -Xmx~{javaMemory}m -jar /opt/picard.jar ExtractIlluminaBarcodes \
      BASECALLS_DIR="Data/Intensities/BaseCalls" \
      TMP_DIR=. \
      OUTPUT_DIR=. \
      BARCODE_FILE="~{barcodeParamsFile}" \
      METRICS_FILE="~{barcodeMetricsFile}" \
      READ_STRUCTURE="~{readStructure}" \
      MAX_MISMATCHES="~{maxMismatches}" \
      MIN_MISMATCH_DELTA="~{minMismatchDelta}" \
      LANE="~{lane}" \
      NUM_PROCESSORS=0 \
      COMPRESSION_LEVEL="~{compressionLevel}" \
      GZIP=true
  >>>

  runtime {
    docker: dockerImage
    disks: "local-disk ~{diskSize} ~{diskType}"
    memory: memory + 'G'
    cpu: 4
  }

  output {
    File barcodes = write_lines(glob("*_barcode.txt.gz"))
    File barcodesInferred = barcodesInferredFile
    File barcodeMetrics = barcodeMetricsFile
    File barcodeParams = barcodeParamsFile
  }
}

task BasecallMetrics {
  input {
    File bcl
    String untarBcl

    File barcodeParams
    File barcodes

    String readStructure
    Int lane

    String dockerImage
  }

  parameter_meta {
    bcl: {
      localization_optional: true
    }
  }

  String basecallMetricsFile = "basecall_metrics.tsv"
  String parsedMetricsFile = "parsed_metrics.tsv"
  String readStatsFile = "read_stats.tsv"

  Int diskSize = ceil(1.9 * size(bcl, 'G') + 5)
  String diskType = if diskSize > 375 then "SSD" else "LOCAL"

  Float memory = 16
  Int javaMemory = ceil((memory * 0.8) * 1000)

  command <<<
    set -e

    # localize inputs
    ~{untarBcl}
    time gsutil -m cp -I . < "~{barcodes}"

    # collect basecall metrics
    java -Xmx~{javaMemory}m -jar /opt/picard.jar CollectIlluminaBasecallingMetrics \
      BASECALLS_DIR="Data/Intensities/BaseCalls" \
      BARCODES_DIR=. \
      TMP_DIR=. \
      INPUT="~{barcodeParams}" \
      OUTPUT="~{basecallMetricsFile}" \
      READ_STRUCTURE="~{readStructure}" \
      LANE="~{lane}"

    # parse read stats and basecall metrics
    python3 <<CODE
    import csv, re
    with open('~{readStatsFile}', 'w') as out:
      reads = list(map(int, re.findall('(\d+)T', '~{readStructure}')))
      reads_count = len(reads)
      writer = csv.writer(out, delimiter='\t', lineterminator='\n')
      writer.writerow([reads_count, float(sum(reads)) / reads_count])
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
    cpu: 2
  }

  output {
    File basecallMetrics = basecallMetricsFile
    File parsedMetrics = parsedMetricsFile
    Int readCount = read_tsv("~{readStatsFile}")[0][0]
    Float meanReadLength = read_tsv("~{readStatsFile}")[0][1]
  }
}

task BasecallsToBams {
  input {
    File bcl
    String untarBcl
    File barcodes

    Array[Array[String]] multiplexParams
    String readStructure
    Int lane

    String sequencingCenter

    String dockerImage
  }

  parameter_meta {
    bcl: {
      localization_optional: true
    }
  }

  String runIdFile = 'run_id.txt'
  String flowcellIdFile = 'flowcell_id.txt'
  String instrumentIdFile = 'instrument_id.txt'

  Int nBarcodes = length(multiplexParams[0]) - 1

  Float bclSize = size(bcl, 'G')

  Int diskSize = ceil(1.9 * bclSize + 5)
  String diskType = if diskSize > 375 then "SSD" else "LOCAL"

  Float memory = ceil(5.4 * bclSize + 147) * 0.25
  Int javaMemory = ceil((memory * 0.9) * 1000)

  command <<<
    set -e

    # localize inputs
    ~{untarBcl}
    time gsutil -m cp -I . < "~{barcodes}"

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
    printf "SAMPLE_ALIAS\tLIBRARY_NAME\tOUTPUT" | tee "${LIBRARY_PARAMS}"
    for i in {1..~{nBarcodes}}; do
      printf "\tBARCODE_%d" "$i" | tee -a "${LIBRARY_PARAMS}"
    done
    while read -r params; do
      name=$(echo "${params}" | cut -d$'\t' -f1)
      barcodes=$(echo "${params}" | cut -d$'\t' -f2-)
      printf "\n%s\t%s\t%s_L%d.bam\t%s" \
        "${name}" "${name}" "${name// /_}" "~{lane}" "${barcodes}" \
        | tee -a "${LIBRARY_PARAMS}"
    done < "~{write_tsv(multiplexParams)}"

    # generate BAMs
    java -Xmx~{javaMemory}m -jar /opt/picard.jar IlluminaBasecallsToSam \
      BASECALLS_DIR="Data/Intensities/BaseCalls" \
      BARCODES_DIR=. \
      TMP_DIR=. \
      LIBRARY_PARAMS="${LIBRARY_PARAMS}" \
      IGNORE_UNEXPECTED_BARCODES=true \
      INCLUDE_NON_PF_READS=false \
      READ_STRUCTURE="~{readStructure}" \
      LANE="~{lane}" \
      RUN_BARCODE="${INSTRUMENT_ID}:${RUN_ID}:${FLOWCELL_ID}" \
      SEQUENCING_CENTER="~{sequencingCenter}"
  >>>

  runtime {
    docker: dockerImage
    disks: "local-disk ~{diskSize} ~{diskType}"
    memory: memory + 'G'
    cpu: 14
  }

  output {
    Array[File] bams = glob("*.bam")
    Int runId = read_int("~{runIdFile}")
    String flowcellId = read_string("~{flowcellIdFile}")
    String instrumentId = read_string("~{instrumentIdFile}")
  }
}

task BamToFastq {
  input {
    Boolean paired

    File bam
    String outputDir

    String dockerImage
  }

  String bamName = basename(bam, ".bam")
  String fastq1 = bamName + "_R1.fastq"
  String fastq2 = bamName + "_R2.fastq"

  command <<<
    set -e

    time samtools fastq -@1 \
      ~{ if paired then '-1 "~{fastq1}" -2 "~{fastq2}"' else '-0 "~{fastq1}"' } \
      "~{bam}"

    BARCODE=$(
      samtools view -H "~{bam}" |
        grep -oh 'PU:\S*' |
        awk -F . '{print $3}' |
        sed 's/-//g'
    )
    convert() {
      awk -v I="$1" -v B="${BARCODE}" '/^@/ {$0=$0" "I":N:0:"B}1' "$2" |
        gzip -n1 > "$2.gz"
    }
    convert 1 "~{fastq1}" & PIDS=$!
    ~{ if paired then 'convert 2 "~{fastq2}" & PIDS="$PIDS $!"' else '' }
    time wait $PIDS

    time gsutil -m cp ./*.fastq.gz "~{outputDir}/"
  >>>

  Int diskMultiplier = if paired then 16 else 8

  runtime {
    docker: dockerImage
    disks: 'local-disk ' + ceil(diskMultiplier * size(bam, 'G')) + ' HDD'
    memory: '1G'
    cpu: 2
  }

  output {
    String libraryName = sub(sub(bamName, "_L\\d+$", ""), "_", " ")
    Array[String] fastqs = if paired then [
      "~{outputDir}/~{fastq1}.gz",
      "~{outputDir}/~{fastq2}.gz",
    ] else [
      "~{outputDir}/~{fastq1}.gz",
    ]
  }
}

task GetLibraryOutputs {
  input {
    String libraryName
    Array[String] fastqs
    File parsedMetrics

    String dockerImage
  }

  String outputsTSV = "outputs.tsv"
  String outputsJSON = "outputs.json"

  command <<<
    set -e

    # header
    printf "%s" "$(head -n1 ~{parsedMetrics})" | tee "~{outputsTSV}"
    for i in {1..~{length(fastqs)}}; do
      printf "\tread%d" "$i" | tee -a "~{outputsTSV}"
    done

    # row with a matching libraryName
    sed 1d "~{parsedMetrics}" | while read -r metrics; do
      name=$(echo "${metrics}" | cut -f1)
      if [ "${name}" == "~{libraryName}" ]; then
        printf "\n%s\t~{sep='\t' fastqs}" "${metrics}" | tee -a "~{outputsTSV}"
        break
      fi
    done

    # convert outputs to JSON
    python3 <<CODE
    import csv, json
    with  open('~{outputsTSV}', 'r') as input, \
          open('~{outputsJSON}', 'w') as output:
      row = next(csv.DictReader(input, delimiter='\t'))
      json.dump(row, output)
    CODE
  >>>

  runtime {
    docker: dockerImage
    disks: "local-disk 1 HDD"
    memory: "1G"
    cpu: 1
  }

  output {
    LibraryOutput out = read_json("~{outputsJSON}")
  }
}

task AggregatePfFragments {
  input {
    Array[Float] pfFragments
    Int nLanes

    String dockerImage
  }

  command <<<
    python3 <<CODE
    sum_fragments = ~{sep="+" pfFragments}
    print(round(sum_fragments / ~{nLanes}E6, 1))
    CODE
  >>>

  runtime {
    docker: dockerImage
    disks: "local-disk 1 HDD"
    memory: "1G"
    cpu: 1
  }

  output {
    Float mPfFragmentsPerLane = read_float(stdout())
  }
}

task OutputJson {
  input {
    PipelineOutputs outputs
    String outputFile

    String dockerImage
  }

  command <<<
    gsutil cp "~{write_json(outputs)}" "~{outputFile}"
  >>>

  runtime {
    docker: dockerImage
    disks: "local-disk 1 HDD"
    memory: "1G"
    cpu: 1
  }
}
