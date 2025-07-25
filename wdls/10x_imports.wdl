version 1.0

struct LaneOutput {
    Int lane
    Array[String] fastqs
    # String barcodeMetrics
    # File basecallMetrics
}

struct PipelineOutputs {
    String workflowType
    String pipelineVersion
    Array[LaneOutput] laneOutputs
    Int r1Length
    Int r2Length
    Int i1Length
    Int i2Length
    # Float meanReadLength
    # Float mPfFragmentsPerLane
    # Int maxMismatches
    # Int minMismatchDelta
    Int runId
    String flowcellId
    String instrumentId
    String runDate
    String? context
}

workflow TenXBclToFastq {
    
    input {
        File bcl               # GCS path to tar.gz of BCLs
        File sampleSheet      # Local path or cloud path to sample sheet
        Array[Int] lanes
        
        # GCS folder where to store the output data
        String outputDir
        String outputJson
        
        String dockerImage
        String pipelineVersion = "KD-v0.1"
        String? context
    }

    scatter (lane in lanes) {
        call BclConvert {
            input:
                bcl = bcl,
                sampleSheet = sampleSheet,
                lane = lane,
                dockerImage = dockerImage
        }
        
        call Transfer {
            input:
                reads = BclConvert.fastqs,
                outputDir = outputDir
        }
        
        LaneOutput laneOutput = object {
            lane: lane,
            fastqs: Transfer.reads,
            # barcodeMetrics: ExtractBarcodes.barcodeMetrics
        }
        
    }

    PipelineOutputs outputs = object {
        workflowType: '10x-import',
        pipelineVersion: pipelineVersion,
        laneOutputs: laneOutput,
        r1Length: BclConvert.r1Length[0],
        r2Length: BclConvert.r2Length[0],
        i1Length: BclConvert.i1Length[0],
        i2Length: BclConvert.i2Length[0],
        # meanReadLength: BasecallMetrics.meanReadLength[0],
        # mPfFragmentsPerLane: AggregatePfFragments.mPfFragmentsPerLane,
        # maxMismatches: p.maxMismatches,
        # minMismatchDelta: p.minMismatchDelta,
        runId: BclConvert.runId[0],
        flowcellId: BclConvert.flowcellId[0],
        instrumentId: BclConvert.instrumentId[0],
        runDate: BclConvert.runDate[0],
        # picardVersion: GetVersion.picard,
        context: context,
    }

    call OutputJson {
        input:
            outputs = outputs,
            outputFile = outputJson,
    }
    
    # output {
    #     Array[File] fastqs = BclConvert.fastqs
    # }
}

task BclConvert {
    input {
        File bcl
        File sampleSheet
        Int lane
        
        # Boolean zipped
        String dockerImage
    }

    String runIdFile = 'run_id.txt'
    String flowcellIdFile = 'flowcell_id.txt'
    String instrumentIdFile = 'instrument_id.txt'

    #String tar_flags = if zipped then 'ixzf' else 'ixf'
    String tar_flags = 'ixf'
    String laneUntarBcl = 'gsutil -m -o GSUtil:parallel_thread_count=1' +
                        ' -o GSUtil:sliced_object_download_max_components=8' +
                        ' cp "~{bcl}" . && ' +
                        'tar "~{tar_flags}" "~{basename(bcl)}" --exclude Images --exclude Thumbnail_Images' +
                        ' RunInfo.xml RTAComplete.txt RunParameters.xml Data/Intensities/s.locs Data/Intensities/BaseCalls/L00~{lane}' +
                        ' && rm "~{basename(bcl)}"'
    
    Float bclSize = size(bcl, 'G')
    Int diskSize = ceil(6.1 * bclSize)
    String diskType = if diskSize > 375 then "SSD" else "LOCAL"

    command <<<
        echo "Downloading BCL tarball from:" ~{bcl}
        ~{laneUntarBcl}
        ls
        
        # extract run parameters
        get_param () {
            param=$(xmlstarlet sel -t -v "/RunInfo/Run/$1" RunInfo.xml)
            echo "${param}" | tee "$2"
        }
        RUN_ID=$(get_param "@Number" "~{runIdFile}")
        FLOWCELL_ID=$(get_param "Flowcell" "~{flowcellIdFile}")
        INSTRUMENT_ID=$(get_param "Instrument" "~{instrumentIdFile}")
        
        files=(r1Length.txt i1Length.txt i2Length.txt r2Length.txt)
        i=0
        xmlstarlet sel -t -v "/RunInfo/Run/Reads/Read/@NumCycles" -n RunInfo.xml | while read num; do
            echo "$num" > "${files[$i]}"
            i=$((i + 1))
        done        

        parse_run_date () {
            run_date="$1"
            year="20${run_date:0:2}"
            month="${run_date:2:2}"
            day="${run_date:4:2}"
            echo "${month}/${day}/${year}"
        }
        runStartDate=$(xmlstarlet sel -t -v "/RunInfo/Run/@Id" RunInfo.xml | awk -F_ '{print $1}')
        parse_run_date $runStartDate > run_date.txt
        
        echo "Running bcl-convert..."
        bcl-convert \
            --bcl-input-directory . \
            --output-directory fastq \
            --sample-sheet ~{sampleSheet} \
            --bcl-only-matched-reads true \
            --bcl-only-lane ~{lane}
    >>>

    output {
        Array[File] fastqs = glob("fastq/*fastq.gz")
        Int runId = read_int("~{runIdFile}")
        String flowcellId = read_string("~{flowcellIdFile}")
        String instrumentId = read_string("~{instrumentIdFile}")
        String runDate = read_string("run_date.txt")
        Int r1Length = read_int("r1Length.txt")
        Int r2Length = read_int("r2Length.txt") 
        Int i1Length = read_int("i1Length.txt")
        Int i2Length = read_int("i2Length.txt") 
    }

    runtime {
        docker: dockerImage
        # TODO: parameterize memory?
        cpu: 16
        memory: "64G"
        disks: "local-disk ~{diskSize} ~{diskType}"
    }
}

task Transfer {
    input {
        Array[File] reads
        String outputDir
    }

    Int diskSize = ceil(size(reads, 'G') * 2.2 + 1)
    String diskType = if diskSize > 375 then "SSD" else "LOCAL"

    command <<<
        for file in ~{sep=' ' reads}; do
            filename=$(basename "$file")
            dest_path="~{outputDir}/$filename"

            echo "Uploading $file to $dest_path"
            gsutil cp "$file" "$dest_path"

            # Record the destination path
            echo "$dest_path" >> gcs_paths.txt
        done
    >>>

    output {
        Array[String] reads = read_lines("gcs_paths.txt")
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