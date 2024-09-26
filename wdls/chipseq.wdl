version 1.0

# Performs alignment of fasta files and BAM postprocessing,
# including sorting, marking duplicates and gathering alignment statistics

### Input types

struct Reference {
    String name

    File fasta

    File amb
    File ann
    File bwt
    File pac
    File sa

    File chromSizes
}

struct LaneSubset {
    String name
    String sampleName
    String libraryName
    String description

    String sequencingCenter
    String? instrumentModel
    String runDate

    Array[File] fastqs
}

### Output types

struct Alignment {
    String laneSubsetName
    String libraryName

    File bam
    File bai

    File alignmentSummaryMetrics
    Int alignedFragments

    File duplicationMetrics
    Int duplicateFragments
    Float percentDuplicateFragments

    Int estimatedLibrarySize
}

struct PredictedEpitope {
    String name
    Float probability
}

struct AlignmentPostProcessing {
    File bam
    File bai
    File? fingerprintFile
    Float? fingerprintSelfLOD

    File alignmentSummaryMetrics
    Int alignedFragments
    Int totalFragments

    File duplicationMetrics
    Int duplicateFragments
    Float percentDuplicateFragments

    Int estimatedLibrarySize

    Array[PredictedEpitope]+? predictedEpitopes

    Float percentMito

    File? insertSizeHistogram

    File? vplot
    Float? vplotScore
}

struct Track {
    File tdf
    File bigWig
}

struct Segmentation {
    String peakStyle
    File? bed
    Float? spot
    Int? segmentCount
}

struct Outputs {
    Map[String, String] softwareVersions
    Map[String, String] commandOutlines

    String genomeName

    Array[Alignment] alignments
    AlignmentPostProcessing alignmentPostProcessing
    Track track
    Array[Segmentation] segmentations

    String? context
}

### Workflow

workflow ChipSeq {
    input {
        # Information about the lane subsets
        Array[LaneSubset] laneSubsets

        # Donor name (used to calculate genotyping fingerprint)
        String? donor

        # Reference genome name
        String genomeName = "hg19"

        # Reference genome FASTA file
        File fasta

        # Parameters of findPeaks task.
        # Ex. ["histone", "factor"]
        Array[String] peakStyles

        # Parameter of find_total_and_compare task
        Int findTotalReads = 5000

        # Docker image URIs
        String dockerImage
        String classifierDockerImage

        # GCS folder in which to store the output JSON
        String outputJsonDir

        # optional context to pass down
        # in workflow outputs
        String? context
    }

    Boolean paired = length(laneSubsets[0].fastqs) == 2

    # Index files bundled with FASTA
    Reference ref = object {
        name: genomeName,
        fasta: fasta,
        amb: fasta + '.amb',
        ann: fasta + '.ann',
        bwt: fasta + '.bwt',
        pac: fasta + '.pac',
        sa: fasta + '.sa',
        chromSizes: fasta + '.chrom.sizes',
    }

    call get_versions {
        input:
            hash = laneSubsets,
            in_docker_image = dockerImage,
    }

    Map[String, String] commandOutlines = {
        "alignment":
            "bwa mem; " +
            "samtools view; " +
            "samtools merge; " +
            "samtools sort; " +
            "picard MarkDuplicates; " +
            "samtools index; " +
            "picard CollectAlignmentSummaryMetrics",
        "alignmentPostProcessing":
            "picard MergeSamFiles; " +
            "picard MarkDuplicates; " +
            "samtools index; " +
            "picard CollectAlignmentSummaryMetrics",
        "track":
            "igvtools count --minMapQuality 1" +
                ( if paired then " --pairs; " else "; " ) +
            "wigToBigWig -clip",
    }

    ### Alignment

    scatter (laneSubset in laneSubsets) {

        call bwa_mem {
            input:
                ref = ref,
                laneSubset = laneSubset,
                dockerImage = dockerImage,
        }

        call samtools_sort {
            input:
                bam = bwa_mem.bam,
                dockerImage = dockerImage,
        }

        call picard_mark_duplicates {
            input:
                bam = samtools_sort.out,
                paired = paired,
                instrumentModel = laneSubset.instrumentModel,
                dockerImage = dockerImage,
        }

        call samtools_index {
            input:
                in_docker_image = dockerImage,
                in_bam = picard_mark_duplicates.out_bam,
        }

        call picard_collect_alignment_summary_metrics as pcasm {
            input:
                in_docker_image = dockerImage,
                in_bam = picard_mark_duplicates.out_bam,
                in_fasta = ref.fasta,
                paired = paired,
        }

        Alignment alignment = object {
            laneSubsetName: laneSubset.name,
            libraryName: laneSubset.libraryName,
            bam: picard_mark_duplicates.out_bam,
            bai: samtools_index.out_bai,
            alignmentSummaryMetrics: pcasm.out_txt,
            alignedFragments: pcasm.aligned_fragments,
            duplicationMetrics: picard_mark_duplicates.metrics,
            duplicateFragments: picard_mark_duplicates.duplicates,
            percentDuplicateFragments: picard_mark_duplicates.percent_duplicates,
            estimatedLibrarySize: picard_mark_duplicates.library_size,
        }
    }

    ### Alignment Post Processing
    #
    # Merges the results of alignments of input fasta files
    # and collects summary alignment results.
    #

    call merge_sam_files {
        input:
            bams = picard_mark_duplicates.out_bam,
            dockerImage = dockerImage,
    }

    call picard_mark_duplicates_filter as picard_mark_duplicates_basic {
        input:
            bam = merge_sam_files.bam,
            paired = paired,
            dockerImage = dockerImage,
    }

    call samtools_index as samtools_index_basic {
        input:
            in_docker_image = dockerImage,
            in_bam = picard_mark_duplicates_basic.out_bam,
    }

    if (genomeName == 'hg19' || genomeName == 'hg38') {
        if (defined(donor)) {
            call genotyping_fingerprint {
                input:
                    bam = picard_mark_duplicates_basic.out_bam,
                    genomeName = genomeName,
                    donor = donor,
                    dockerImage = dockerImage,
            }
        }
    }

    if (genomeName == "hg19") {
        call epitope_classifier {
            input:
                in_docker_image = classifierDockerImage,
                in_bam = picard_mark_duplicates_basic.out_bam,
                in_bai = samtools_index_basic.out_bai,
                in_chrom_sizes = ref.chromSizes,
        }
    }

    call vplot {
        input:
            bam = picard_mark_duplicates_basic.out_bam,
            bai = samtools_index_basic.out_bai,
            genomeName = genomeName,
            dockerImage = dockerImage,
    }

    call mito {
        input:
            dockerImage = dockerImage,
            bam = picard_mark_duplicates_basic.out_bam,
            bai = samtools_index_basic.out_bai,
    }

    if (paired) {
        call insert_size_metrics {
            input:
                dockerImage = dockerImage,
                bam = picard_mark_duplicates_basic.out_bam,
                bamName = laneSubsets[0].libraryName,
        }
    }

    call picard_collect_alignment_summary_metrics as aggregated_alignment_metrics {
        input:
            in_docker_image = dockerImage,
            in_bam = picard_mark_duplicates_basic.out_bam,
            in_fasta = ref.fasta,
            paired = paired,
    }

    AlignmentPostProcessing alignmentPostProcessing = object {
        bam: picard_mark_duplicates_basic.out_bam,
        bai: samtools_index_basic.out_bai,
        fingerprintFile: genotyping_fingerprint.out_bam,
        fingerprintSelfLOD: genotyping_fingerprint.self_lod,
        alignmentSummaryMetrics: aggregated_alignment_metrics.out_txt,
        alignedFragments: picard_mark_duplicates_basic.aligned_fragments,
        totalFragments: picard_mark_duplicates_basic.total_fragments,
        duplicationMetrics: picard_mark_duplicates_basic.metrics,
        duplicateFragments: picard_mark_duplicates_basic.duplicates,
        percentDuplicateFragments: picard_mark_duplicates_basic.percent_duplicates,
        estimatedLibrarySize: picard_mark_duplicates_basic.library_size,
        predictedEpitopes: epitope_classifier.predictedEpitopes,
        percentMito: mito.percent,
        insertSizeHistogram: insert_size_metrics.histogram,
        vplot: vplot.png,
        vplotScore: vplot.score,
    }

    ### Track

    call igvtools_count {
        input:
            in_docker_image = dockerImage,
            in_paired = paired,
            in_read_length = merge_sam_files.readLength,
            in_bam = picard_mark_duplicates_basic.out_bam,
            in_chrom_sizes = ref.chromSizes,
    }

    call wigtobigwig {
        input:
            in_docker_image = dockerImage,
            in_wig = igvtools_count.out_wig,
            in_chrom_sizes = ref.chromSizes,
    }

    Track track = object {
        tdf: igvtools_count.out_tdf,
        bigWig: wigtobigwig.out_bw,
    }

    ### Segmentation
    #
    # Performs HOMER segmentation for each segmenter style.
    #

    call find_total_and_compare {
        input:
            in_docker_image = dockerImage,
            metric_txt = aggregated_alignment_metrics.out_txt,
            in_paired = paired,
            req_total_reads = findTotalReads,
    }

    if (find_total_and_compare.isTotalGreater) {

        call makeTagDirectory {
            input:
                in_docker_image = dockerImage,
                in_bam = picard_mark_duplicates_basic.out_bam,
        }

        scatter (peakStyle in peakStyles) {

            call findPeaks {
                input:
                    in_docker_image = dockerImage,
                    style = peakStyle,
                    in_txt_files = makeTagDirectory.output_txt,
                    in_tsv_file = makeTagDirectory.output_tsv,
            }

            call pos2bed {
                input:
                    in_docker_image = dockerImage,
                    temp_file = findPeaks.out_temp,
            }

            call filter_negatives {
                input:
                    in_docker_image = dockerImage,
                    temp_file = pos2bed.out_temp_bed,
            }

            call enough_lines {
                input:
                    in_docker_image = dockerImage,
                    temp_file = filter_negatives.filter_negatives_bed,
            }

            if (enough_lines.tempFileIsNotEmpty) {

                call sort_bed as sort_result_file {
                    input:
                        in_docker_image = dockerImage,
                        temp_bed_file = filter_negatives.filter_negatives_bed,
                }

                call get_segs {
                    input:
                        in_docker_image = dockerImage,
                        input_file = filter_negatives.filter_negatives_bed,
                }

                call bam_has_chr {
                    input:
                        in_docker_image = dockerImage,
                        in_bam = picard_mark_duplicates_basic.out_bam,
                }

                call bed_has_chr {
                    input:
                        in_docker_image = dockerImage,
                        in_bed = sort_result_file.out_bed_sorted,
                }

                call sort_and_merge_bed {
                    input:
                        in_docker_image = dockerImage,
                        temp_bed_file = sort_result_file.out_bed_sorted,
                }

                if (bed_has_chr.out && !bam_has_chr.out) {

                    call if_bed_has_chr {
                        input:
                            in_docker_image = dockerImage,
                            input_file = sort_and_merge_bed.merged_bed,
                    }

                    call intersect_Bed as intersect_Bed_bed {
                        input:
                            in_docker_image = dockerImage,
                            input_file = if_bed_has_chr.out,
                            bam_file = picard_mark_duplicates_basic.out_bam,
                    }

                    call samtools_view_cF_1540 as samtools_view_cF_1540_bed {
                        input:
                            in_docker_image = dockerImage,
                            input_file = intersect_Bed_bed.out,
                    }
                }

                if (bam_has_chr.out && !bed_has_chr.out) {

                    call if_bam_has_chr {
                        input:
                            in_docker_image = dockerImage,
                            input_file = sort_and_merge_bed.merged_bed,
                    }

                    call intersect_Bed as intersect_Bed_bam {
                        input:
                            in_docker_image = dockerImage,
                            input_file = if_bam_has_chr.out,
                            bam_file = picard_mark_duplicates_basic.out_bam,
                    }

                    call samtools_view_cF_1540 as samtools_view_cF_1540_bam {
                        input:
                            in_docker_image = dockerImage,
                            input_file = intersect_Bed_bam.out,
                    }
                }

                if ( (bam_has_chr.out && bed_has_chr.out) || (!bam_has_chr.out && !bed_has_chr.out) ) {

                    call intersect_Bed as intersect_Bed__ {
                        input:
                            in_docker_image = dockerImage,
                            input_file = sort_and_merge_bed.merged_bed,
                            bam_file = picard_mark_duplicates_basic.out_bam,
                    }

                    call samtools_view_cF_1540 as samtools_view_cF_1540__ {
                        input:
                            in_docker_image = dockerImage,
                            input_file = intersect_Bed__.out,
                    }
                }

                call samtools_view_cF_1540 as samtools_view_cF_1540_main_bam {
                    input:
                        in_docker_image = dockerImage,
                        input_file = picard_mark_duplicates_basic.out_bam,
                }

                Int count = select_first([
                    samtools_view_cF_1540_bed.result,
                    samtools_view_cF_1540_bam.result,
                    samtools_view_cF_1540__.result,
                ])

                Float spot = count * 1.0 / samtools_view_cF_1540_main_bam.result
            }

            Segmentation segmentation = object {
                peakStyle: peakStyle,
                bed: sort_result_file.out_bed_sorted,
                spot: spot,
                segmentCount: get_segs.count,
            }
        }
    }

    Outputs out = object {
        softwareVersions: get_versions.out,
        commandOutlines: commandOutlines,
        genomeName: genomeName,
        alignments: alignment,
        alignmentPostProcessing: alignmentPostProcessing,
        track: track,
        segmentations: select_first([segmentation]),
        context: context,
    }

    call output_json {
        input:
            json = write_json(out),
            dir = outputJsonDir,
    }

    output {
        Outputs outputs = out
    }
}

### Tasks

task get_versions {
    input {
        # This parameter is used to bust undesirable
        # call-caching on this task; otherwise,
        # it takes a long time to invalidate previous
        # call entries, after we delete
        # execution files on a schedule
        Array[LaneSubset] hash

        String in_docker_image
    }

    parameter_meta {
        hash: {
            localization_optional: true
        }
    }

    command {
        cat /opt/versions.tsv
    }

    runtime {
        docker: in_docker_image
    }

    output {
        Map[String, String] out = read_map(stdout())
    }
}

task trim_adapter {
    input {
        Array[File]+ fastqs
        Boolean paired
    }

    Int memory = 8
    Int cpu = 8

    command <<<
        encode_trim_adapter.py \
            '~{write_tsv([fastqs])}' \
            ~{if paired then '--paired-end' else ''} \
            --auto-detect-adapter \
            --nth ~{cpu}
	>>>

	runtime {
        docker: 'quay.io/encode-dcc/atac-seq-pipeline:v1.4.2'
        disks: 'local-disk 1 HDD'
        memory: memory + 'G'
		cpu: cpu
	}

    output {
        Array[File]+ trimmed = glob("**/*.trim.merged.fastq.gz")
	}
}

task bwa_mem {
    input {
        Reference ref
        LaneSubset laneSubset

        String dockerImage
    }

    Array[String] header = [
        '@RG',
        'ID:' + laneSubset.name,
        'SM:' + laneSubset.sampleName,
        'LB:' + laneSubset.libraryName,
        'DS:' + laneSubset.description,
        'PL:' + 'ILLUMINA',
        'CN:' + laneSubset.sequencingCenter,
        'DT:' + laneSubset.runDate,
        'UR:' + sub(ref.fasta, 'gs:', ''),
        'AS:' + ref.name,
        'PG:' + 'bwa',
    ]

    Float fastqSize = size(laneSubset.fastqs, 'G')
    Float refSize = size([ref.fasta, ref.bwt, ref.pac, ref.sa], 'G')
    Float memSize = 2 * refSize + 0.5 * fastqSize

    Int cpu = 16

    String outBam = 'out.bam'

    command <<<
        set -e

        printf '~{sep="\\\\t" header}\\tPU:' > 'header.txt'

        # extract Platform Unit from the 1st Fastq
        gunzip -c '~{laneSubset.fastqs[0]}' |
            head -1 |
            awk -F: '{print $3,$4,$10}' OFS=. |
            tee -a 'header.txt'

        bwa mem \
            -t ~{cpu} \
            -M \
            -K 75000000 \
            -R "$(< header.txt)" \
            '~{ref.fasta}' \
            '~{sep="' '" laneSubset.fastqs}' |
            samtools view -bhS > '~{outBam}'
    >>>

    runtime {
        docker: dockerImage
        disks: 'local-disk ' + ceil(2.5 + refSize + 2.5 * fastqSize) + ' HDD'
        memory: ceil(if fastqSize < 1 then 2 * memSize else memSize) + 'G'
        cpu: cpu
    }

    output {
        File bam = outBam
    }
}

task samtools_sort {
    input {
        File bam

        String dockerImage
    }

    Int cpu = 4

    String outBam = 'out.bam'

    command <<<
        samtools sort -@ ~{cpu} \
            -T 'tmp' '~{bam}' > '~{outBam}'
    >>>

    runtime {
        docker: dockerImage
        disks: 'local-disk ' + ceil(3 + 2.5 * size(bam, 'G')) + ' HDD'
        memory: '16G'
        cpu: cpu
    }

    output {
        File out = outBam
    }
}

# Runs MarkDuplicates tool from Picard Tools.
# This task processes an input file BAM file
# and creates a new file, where SAM flag set for reads,
# detected as duplicates.
#
# Also outputs a metrics file
# containing BAM file duplicates statistics

task picard_mark_duplicates {
    input {
        File bam
        Boolean paired
        String? instrumentModel

        String dockerImage
    }

    String duplicatesKey = if paired
        then "READ_PAIR_DUPLICATES"
        else "UNPAIRED_READ_DUPLICATES"

    Int opticalPixelDistance = if select_first([instrumentModel, 'Unknown']) == 'NovaSeq' then 2500 else 100

    String outBam = 'out.bam'

    Float bamSize = size(bam, 'G')
    Int diskSize = ceil(8.5 + 2 * bamSize)

    Int memSize = ceil(3.5 + 17 * bamSize)
    Int javeMemMB = ceil((memSize * 0.9) * 1000)

    command <<<
        java -Xmx~{javeMemMB}m -jar /opt/picard.jar \
            MarkDuplicates \
                INPUT='~{bam}' \
                OUTPUT='~{outBam}' \
                METRICS_FILE=metrics.txt \
                VALIDATION_STRINGENCY=LENIENT \
                OPTICAL_DUPLICATE_PIXEL_DISTANCE=~{opticalPixelDistance}

        sed '/^\(#.*\|\)$/d' metrics.txt | \
            awk -F '\t' '
                NR==1 {
                    for (i=1; i<=NF; i++) {
                        ix[$i] = i
                    }
                }
                NR==2 {
                    print   $ix["~{duplicatesKey}"],
                            $ix["PERCENT_DUPLICATION"] * 100,
                            $ix["ESTIMATED_LIBRARY_SIZE"] * 1;
                    exit
                }' | \
            tee counts.txt
        awk '{ print $1 }' counts.txt > duplicates.txt
        awk '{ print $2 }' counts.txt > percent_duplicates.txt
        awk '{ print $3 }' counts.txt > library_size.txt
    >>>

    runtime {
        docker: dockerImage
        disks: "local-disk ~{diskSize} HDD"
        memory: memSize + "Gi"
    }

    output {
        File out_bam = outBam
        File metrics = "metrics.txt"
        Int duplicates = read_int("duplicates.txt")
        Float percent_duplicates = read_float("percent_duplicates.txt")
        Int library_size = if paired then read_int("library_size.txt") else 0
    }
}

task picard_mark_duplicates_filter {
    input {
        File bam
        Boolean paired
        String? instrumentModel

        String dockerImage
    }

    String duplicatesKey = if paired
        then "READ_PAIR_DUPLICATES"
        else "UNPAIRED_READ_DUPLICATES"

    Int opticalPixelDistance = if select_first([instrumentModel, 'Unknown']) == 'NovaSeq' then 2500 else 100

    String outBam = 'out.bam'

    Float bamSize = size(bam, 'G')
    Int diskSize = ceil(8.5 + 5 * bamSize)

    Int memSize = ceil(3.5 + 17 * bamSize)
    Int javeMemMB = ceil((memSize * 0.9) * 1000)

    command <<<
        tot=$(samtools view -c '~{bam}')
        if [ '~{paired}' == 'true' ]
        then
            samtools view -F 1804 -f 2 -u '~{bam}' | samtools sort -n > tmp.filtered1.bam
            samtools fixmate -r tmp.filtered1.bam tmp.fixed.bam
            rm tmp.filtered1.bam
            samtools view -F 1804 -f 2 -u tmp.fixed.bam | samtools sort > tmp.filtered.bam
            rm tmp.fixed.bam
            aln=$(samtools view -c -F 780 -f 2 tmp.filtered.bam)
        else
            samtools view -F 1804 -b '~{bam}' > tmp.filtered.bam
            aln=$(samtools view -c -F 780 tmp.filtered.bam)
        fi

        java -Xmx~{javeMemMB}m -jar /opt/picard.jar \
            MarkDuplicates \
                INPUT=tmp.filtered.bam \
                OUTPUT=tmp.marked.bam \
                METRICS_FILE=metrics.txt \
                VALIDATION_STRINGENCY=LENIENT \
                OPTICAL_DUPLICATE_PIXEL_DISTANCE=~{opticalPixelDistance}
        rm tmp.filtered.bam

        sed '/^\(#.*\|\)$/d' metrics.txt | \
            awk -F '\t' '
                NR==1 {
                    for (i=1; i<=NF; i++) {
                        ix[$i] = i
                    }
                }
                NR==2 {
                    print   $ix["~{duplicatesKey}"],
                            $ix["PERCENT_DUPLICATION"] * 100,
                            $ix["ESTIMATED_LIBRARY_SIZE"] * 1;
                    exit
                }' | \
            tee counts.txt

        # awk '{ print $1 }' counts.txt > duplicates.txt
        # awk '{ print $2 }' counts.txt > percent_duplicates.txt
        awk '{ print $3 }' counts.txt > library_size.txt

        dup=$(samtools view -c -f 1024 tmp.marked.bam)
        expr=$(printf 'cat(round(%s/%s*100,4))' $dup $aln)
        Rscript -e $expr > percent_duplicates.txt

        if [ '~{paired}' == 'true' ]
        then
            samtools view -F 1804 -f 2 -b tmp.marked.bam > '~{outBam}'
            echo $(($tot / 2)) > total_fragments.txt
            echo $(($aln / 2)) > aligned_fragments.txt
            echo $(($dup / 2)) > duplicates.txt

        else
            samtools view -F 1804 -b tmp.marked.bam > '~{outBam}'
            echo $(($tot)) > total_fragments.txt
            echo $aln > aligned_fragments.txt
            echo $dup > duplicates.txt
        fi
    >>>

    runtime {
        docker: dockerImage
        disks: "local-disk ~{diskSize} HDD"
        memory: memSize + "Gi"
    }

    output {
        File out_bam = outBam
        File metrics = "metrics.txt"
        Int total_fragments = read_int("total_fragments.txt")
        Int aligned_fragments = read_int("aligned_fragments.txt")
        Int duplicates = read_int("duplicates.txt")
        Float percent_duplicates = read_float("percent_duplicates.txt")
        Int library_size = if paired then read_int("library_size.txt") else 0
    }
}


# Builds 'bai' index for an input BAM file using 'samtools index' command

task samtools_index {
    input {
        String in_docker_image

        File in_bam
    }

    Int diskSize = ceil(1.5 * size(in_bam, 'G'))

    command {
        samtools index '~{in_bam}' 'out.bai'
    }

    runtime {
        docker: in_docker_image
        disks: "local-disk ~{diskSize} HDD"
    }

    output {
        File out_bai = "out.bai"
    }
}

task genotyping_fingerprint {
    input {
        File bam
        String genomeName # hg19 or hg38 required
        String? donor
        String dockerImage
    }

    Float bamSize = size(bam, 'G')
    Int cpu = 4
    Float memory = 15
    Int javaMemory = ceil((memory * 0.8) * 1000)

    String fingerprintBam = 'fingerprint.bam'
    String lodOut = 'self_lod.txt'

    command <<<
        set -euo pipefail

        count=$(samtools view -c -f 1 '~{bam}')
        if [ "$count" -eq "0" ]; then
            bed_cmd='intersectBed -wa'
        else
            bed_cmd='pairToBed'
        fi
        samtools sort -@~{cpu} -n '~{bam}' |
        ${bed_cmd} -abam stdin -b '/opt/genotyping/~{genomeName}_nochr.bed' |
        samtools sort -@~{cpu} -o 'sorted.bam'

        java -Xmx~{javaMemory}m -jar /opt/picard.jar \
            MarkDuplicates \
                INPUT='sorted.bam' \
                OUTPUT='out.bam' \
                METRICS_FILE='metrics.txt' \
                REMOVE_DUPLICATES=TRUE \
                VALIDATION_STRINGENCY=SILENT

        samtools reheader \
            -c 'sed -E "s|(\tSM:)[^\t]+|\1~{donor}|"' 'sorted.bam' \
            > '~{fingerprintBam}'

        samtools index '~{fingerprintBam}'

        java -Xmx~{javaMemory}m -jar /opt/picard.jar \
            CrosscheckFingerprints \
            INPUT='~{fingerprintBam}' \
            HAPLOTYPE_MAP='/opt/genotyping/~{genomeName}_nochr.map' \
            CROSSCHECK_BY=FILE \
            VALIDATION_STRINGENCY=LENIENT \
            NUM_THREADS=~{cpu} \
            | grep -v ^$ | tail -1 \
            | awk -F '\t' '{print $5}' > '~{lodOut}'
    >>>

    runtime {
        docker: dockerImage
        disks: 'local-disk ' + ceil(3 * bamSize + 6) + ' HDD'
        memory: memory + 'G'
        cpu: cpu
    }

    output {
        File out_bam = fingerprintBam
        Float self_lod = read_float('~{lodOut}')
    }
}

task epitope_classifier {
    input {
        String in_docker_image

        File in_bam
        File in_bai

        File in_chrom_sizes
    }

    Int diskSize = ceil(1.5 * size([in_bam, in_bai], 'G'))

    command <<<
        classify.sh '~{in_bam}' '~{in_bai}' /tmp '~{in_chrom_sizes}' \
            | tail -n1 | tee results.txt
        awk '{ print $2 }' results.txt > epitope_1.txt
        awk '{ print $3 }' results.txt > probability_1.txt
        awk '{ print $4 }' results.txt > epitope_2.txt
        awk '{ print $5 }' results.txt > probability_2.txt
    >>>

    runtime {
        docker: in_docker_image
        disks: "local-disk ~{diskSize} HDD"
    }

    output {
        Array[PredictedEpitope] predictedEpitopes = [
            object {
                name: read_string("epitope_1.txt"),
                probability:  read_float("probability_1.txt"),
            },
            object {
                name: read_string("epitope_2.txt"),
                probability:  read_float("probability_2.txt"),
            },
        ]
    }
}

task insert_size_metrics {
    input {
        File bam
        String bamName

        String dockerImage
    }

    Int diskSize = ceil(1.25 * size(bam, 'G'))
    Int memory = 3500
    Int javaMemory = ceil(memory * 0.8)

    String histName = 'histogram.pdf'
    String metricsName = 'metrics.txt'

    command <<<
        set -e

        mv '~{bam}' '~{bamName}'

        java -Xmx~{javaMemory}m -jar /opt/picard.jar \
            CollectInsertSizeMetrics \
                INPUT='~{bamName}' \
                HISTOGRAM_FILE='~{histName}' \
                OUTPUT='~{metricsName}' \
                VALIDATION_STRINGENCY=LENIENT \
                STOP_AFTER=20000000 \
                W=1000
    >>>

    runtime {
        docker: dockerImage
        disks: "local-disk ~{diskSize} HDD"
        memory: memory + "M"
        cpu: 1
    }

    output {
        File histogram = histName
        File metrics = metricsName
    }
}

task mito {
    input {
        File bam
        File bai

        String dockerImage
    }

    Int diskSize = ceil(1.25 * size(bam, 'G'))

    String outPercent = 'percent.txt'
    String outStats = 'stats.txt'

    command <<<
        set -e

        mv "~{bam}" in.bam
        mv "~{bai}" in.bai

        samtools idxstats "in.bam" > "~{outStats}"
        calcPctMito.R "~{outStats}" > "~{outPercent}"
    >>>

    runtime {
        docker: dockerImage
        disks: "local-disk ~{diskSize} HDD"
        memory: "1G"
        cpu: 1
    }

    output {
        Float percent = read_float("~{outPercent}")
        File stats = outStats
    }
}

# Currently, requires hg19
task vplot {
    input {
        File bam
        File bai

        String genomeName

        String dockerImage
    }

    Int cpu = 4
    Int memory = ceil(1.25 * size(bam, 'M'))
    Int diskSize = ceil(1.5 * size(bam, 'G'))

    String outStats = 'stats.txt'
    String outPng = outStats + '.png'
    String outScore = 'score.txt'

    command <<<
        set -e

        mv "~{bam}" in.bam
        mv "~{bai}" in.bai

        pyMakeVplot \
            -a "in.bam" \
            -b "/opt/refGene_~{genomeName}_TSS.no_chr.sorted.bed" \
            -o "~{outStats}" \
            -e 5000 \
            -p ends \
            -c ~{cpu} \
            -v \
            -u

        calcTssScore.R \
            "~{outStats}" > "~{outScore}"
    >>>

    runtime {
        docker: dockerImage
        disks: "local-disk ~{diskSize} HDD"
        memory: memory + "M"
        cpu: cpu
    }

    output {
        File png = outPng
        Float score = read_float("~{outScore}")
        File stats = outStats
    }
}

# Runs CollectAlignmentSummaryMetrics from Picard Tools.
# This tool produces metrics detailing the quality of the read alignments
# as well as the proportion of the reads that passed machine signal-to-noise
# threshold quality filters.
# Metric outputs result in a text format, containing input file statistics.

task picard_collect_alignment_summary_metrics {
    input {
        String in_docker_image

        File in_bam
        File in_fasta
        Boolean paired
    }

    String category = if paired then "FIRST_OF_PAIR" else "UNPAIRED"
    String alignedKey = if paired then "READS_ALIGNED_IN_PAIRS" else "PF_READS_ALIGNED"

    Int memory = 4
    Int javaMemory = ceil((memory * 0.8) * 1000)
    Int diskSize = ceil(1.5 * size([in_bam, in_fasta], 'G'))

    command <<<
        java -Xmx~{javaMemory}m -jar /opt/picard.jar \
            CollectAlignmentSummaryMetrics \
                INPUT='~{in_bam}' \
                METRIC_ACCUMULATION_LEVEL=LIBRARY \
                METRIC_ACCUMULATION_LEVEL=READ_GROUP \
                OUTPUT=metrics.txt \
                VALIDATION_STRINGENCY=LENIENT \
                REFERENCE_SEQUENCE='~{in_fasta}'

        sed '/^\(#.*\|\)$/d' metrics.txt | \
            awk '
                NR==1 {
                    for (i=1; i<=NF; i++) {
                        ix[$i] = i
                    }
                }
                $ix["CATEGORY"]=="~{category}" {
                    print   $ix["TOTAL_READS"],
                            $ix["~{alignedKey}"];
                    exit
                }' | \
            tee counts.txt
        awk '{ print $1 }' counts.txt > total_reads.txt
        awk '{ print $2 }' counts.txt > aligned_fragments.txt
    >>>

    runtime {
        docker: in_docker_image
        disks: "local-disk ~{diskSize} HDD"
        memory: memory + "G"
    }

    output {
        File out_txt = "metrics.txt"
        Int total_reads = read_int("total_reads.txt")
        Int aligned_fragments = read_int("aligned_fragments.txt")
    }
}

task merge_sam_files {
    input {
        Array[File] bams

        String dockerImage
    }

    Float diskSize = size(bams, 'G')

    String outBam = 'out.bam'
    String readLenFile = 'read_length.txt'

    command <<<
        set -e

        java -Xmx900m -jar /opt/picard.jar \
            MergeSamFiles \
                OUTPUT='~{outBam}' \
                USE_THREADING=true \
                MERGE_SEQUENCE_DICTIONARIES=true \
                VALIDATION_STRINGENCY=LENIENT \
                INPUT='~{sep="' INPUT='" bams}'

        samtools view '~{outBam}' \
            | awk '{print length($10)}' \
            | head -1 \
            > '~{readLenFile}'
    >>>

    runtime {
        docker: dockerImage
        disks: "local-disk " + ceil(2 + 2 * diskSize) + " HDD"
        memory: "1G"
        cpu: 1
    }

    output {
        File bam = outBam
        Int readLength = read_int('~{readLenFile}')
    }
}

task igvtools_count {
    input {
        String in_docker_image

        File in_bam
        File in_chrom_sizes
        Boolean in_paired
        Int in_read_length
    }

    String pairs = if in_paired then "--pairs" else ""
    String read_ext = if in_paired then "" else "-e ~{200 - in_read_length}"

    Int diskSize = ceil(3.5 * size(in_bam, 'M') / 1000)

    command {
        if [ '~{in_paired}' == 'true' ]
        then
            samtools view -F 1804 -f 2 -q30 -b '~{in_bam}' > tmp.filtered.bam
        else
            samtools view -F 1804 -q 30 -b '~{in_bam}' > tmp.filtered.bam
        fi

        igvtools count ~{read_ext} \
            ~{pairs} \
            tmp.filtered.bam \
            out.wig,out.tdf \
            '~{in_chrom_sizes}'
    }

    runtime {
        docker: in_docker_image
        disks: "local-disk ~{diskSize} HDD"
    }

    output {
        File out_wig = "out.wig"
        File out_tdf = "out.tdf"
    }
}

task wigtobigwig {
    input {
        String in_docker_image

        File in_wig
        File in_chrom_sizes
    }

    Int diskGB = ceil(2.5 * size(in_wig, 'G'))
    Int memMB = ceil(5 * size(in_wig, "M"))

    command {
        wigToBigWig -clip \
            '~{in_wig}' \
            '~{in_chrom_sizes}' \
            "out_track.bw"
    }

    runtime {
        docker: in_docker_image
        disks: "local-disk ~{diskGB} HDD"
        memory: memMB + "M"
    }

    output {
        File out_bw = "out_track.bw"
    }
}

task find_total_and_compare {
    input {
        String in_docker_image

        Int req_total_reads
        File metric_txt
        Boolean in_paired
    }

    String of_pair = if (in_paired) then "FIRST_OF_PAIR" else "UNPAIRED"

    command {
        java -Xmx1500m -jar /opt/find_total.jar \
            '~{metric_txt}' PF_READS ~{of_pair} > total.txt
    }

    runtime {
        docker: in_docker_image
        disks: "local-disk 1 HDD"
    }

    output {
        Boolean isTotalGreater = read_int("total.txt") > req_total_reads
    }
}

task makeTagDirectory {
    input {
        String in_docker_image

        File in_bam
    }

    command {
        makeTagDirectory . -single '~{in_bam}'
    }

    runtime {
        docker: in_docker_image
        disks: 'local-disk 375 LOCAL'
        memory: ceil(2 * size(in_bam, 'G') + 1) + 'G'
    }

    output {
        File output_tsv = "genome.tags.tsv"
        Array[File] output_txt = glob("*.txt")
    }
}

task findPeaks {
    input {
        String in_docker_image

        Array[File] in_txt_files
        File in_tsv_file

        String style
    }

    Float filesSize = size(flatten([
        in_txt_files,
        [in_tsv_file],
    ]), 'G')

    command {
        mv '~{in_tsv_file}' '~{sep="' '" in_txt_files}' -t .
        findPeaks . -o HOMER_temp -style ~{style}
    }

    runtime {
        docker: in_docker_image
        disks: 'local-disk ' + ceil(0.2 + 1.0 * filesSize) + ' HDD'
        memory: ceil(3 + 2.1 * filesSize) + 'Gi'
    }

    output {
        File out_temp = "HOMER_temp"
    }
}

task pos2bed {
    input {
        String in_docker_image

        File temp_file
    }

    command {
        pos2bed.pl -bed '~{temp_file}'
        mv '~{temp_file}.bed' -t .
    }

    runtime {
        docker: in_docker_image
        disks: "local-disk 1 HDD"
    }

    output {
        File out_temp_bed = "HOMER_temp.bed"
    }
}

task filter_negatives {
    input {
        String in_docker_image

        File temp_file
    }

    command <<<
        awk '{if(!($3<0 || $4<0)) {print $0}}' \
            '~{temp_file}' > filter_negatives.bed
    >>>

    runtime {
        docker: in_docker_image
        disks: "local-disk 1 HDD"
    }

    output {
        File filter_negatives_bed = "filter_negatives.bed"
    }
}

task enough_lines {
    input {
        String in_docker_image

        File temp_file
    }

    command {
        wc -l < '~{temp_file}' > count.txt
    }

    runtime {
        docker: in_docker_image
        disks: "local-disk 1 HDD"
    }

    output {
        Boolean tempFileIsNotEmpty = read_int("count.txt") > 0
    }
}

task sort_bed {
    input {
        String in_docker_image

        File temp_bed_file
    }

    command {
        sortBed -i '~{temp_bed_file}' > sorted.bed
    }

    runtime {
        docker: in_docker_image
        disks: "local-disk 1 HDD"
    }

    output {
        File out_bed_sorted = "sorted.bed"
    }
}

task get_segs {
    input {
        String in_docker_image

        File input_file
    }

    command {
        wc -l < '~{input_file}' > count.txt
    }

    runtime {
        docker: in_docker_image
        disks: "local-disk 1 HDD"
    }

    output {
        Int count = read_int("count.txt")
    }
}

task bam_has_chr {
    input {
        String in_docker_image

        File in_bam
    }

    Int diskSize = ceil(1.5 * size(in_bam, 'G'))

    command <<<
        samtools view '~{in_bam}' \
            | head -1 \
            | awk '$3 ~ /^chr/ {print "true"}' \
            > has_chr.txt
    >>>

    runtime {
        docker: in_docker_image
        disks: "local-disk ~{diskSize} HDD"
    }

    output {
        Boolean out = read_string("has_chr.txt") == "true"
    }
}

task bed_has_chr {
    input {
        String in_docker_image

        File in_bed
    }

    command <<<
        head -1 < '~{in_bed}' \
            | awk '$1 ~ /^chr/ {print "true"}' \
            > has_chr.txt
    >>>

    runtime {
        docker: in_docker_image
        disks: "local-disk 1 HDD"
    }

    output {
        Boolean out = read_string("has_chr.txt") == "true"
    }
}

task sort_and_merge_bed {
    input {
        String in_docker_image

        File temp_bed_file
    }

    command {
        mergeBed -i '~{temp_bed_file}' > result_merge.bed
    }

    runtime {
        docker: in_docker_image
        disks: "local-disk 1 HDD"
    }

    output {
        File merged_bed = "result_merge.bed"
    }
}

task if_bam_has_chr {
    input {
        String in_docker_image

        File input_file
    }

    command <<<
        awk 'BEGIN {OFS="\t"} {print "chr"$0}' '~{input_file}'  > result
    >>>

    runtime {
        docker: in_docker_image
        disks: "local-disk 1 HDD"
    }

    output {
        File out = "result"
    }
}

task if_bed_has_chr {
    input {
        String in_docker_image

        File input_file
    }

    command <<<
        awk 'BEGIN {OFS="\t"} {split($1,arr,"chr");print arr[2],$2,$3}' \
            '~{input_file}' > result
    >>>

    runtime {
        docker: in_docker_image
        disks: "local-disk 1 HDD"
    }

    output {
        File out = "result"
    }
}

task intersect_Bed {
    input {
        String in_docker_image

        File input_file
        File bam_file
    }

    Int diskSize = ceil(2.5 * size(bam_file, 'G'))

    command {
        intersectBed -abam '~{bam_file}' \
            -b '~{input_file}' > intersect_Bed_stdout
    }

    runtime {
        docker: in_docker_image
        disks: "local-disk ~{diskSize} HDD"
    }

    output {
        File out = "intersect_Bed_stdout"
    }
}

task samtools_view_cF_1540 {
    input {
        String in_docker_image

        File input_file
    }

    Int diskSize = ceil(1.5 * size(input_file, 'G'))

    command {
        samtools view -c -F 1540 '~{input_file}' > result.txt
    }

    runtime {
        docker: in_docker_image
        disks: "local-disk ~{diskSize} HDD"
    }

    output {
        Int result = read_int("result.txt")
    }
}

task output_json {
  input {
    File json
    String dir
  }

  command <<<
    gsutil cp "~{json}" "~{dir}/"
  >>>

  runtime {
    docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:alpine"
    disks: "local-disk 1 HDD"
    memory: "1G"
  }
}