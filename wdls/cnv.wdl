version 1.0

struct PredictedEpitope {
    String name
    Float probability
}

struct Outputs {
  String binnedBed
  Float signalToNoiseRatio
  String? cnvRatiosBed
  Boolean cnvsDetected
  String fittingParams
  String pbsBed
  Array[PredictedEpitope]+ predictedEpitopes
  String? context
}

workflow CNVAnalysis {
  input {
    # Alignment Post Processing BAM
    File bam

    # CNV Ratios BED (absent for input controls)
    File? cnvRatiosBed

    String genomeName = 'hg19'

    Int binSize = 5000

    Boolean bypassCNVRescalingStep

    String dockerImage

    # GCS folder in which to store the output files
    String outFilesDir

    # GCS folder in which to store the output JSON
    String outJsonDir

    # optional context used to trace workflow outputs
    String? context
  }

  String outPrefix = basename(bam, '.bam')

}

task binning {
  input {
    File bam
    String outPrefix
    String genomeName
    Int binSize

    String dockerImage
  }

  String outSuffix = 'binned'

  command <<<
    /scripts/binning/bin.sh \
      -f '~{bam}' \
      -g ~{genomeName} \
      -n ~{outPrefix} \
      -s ~{outSuffix} \
      -w ~{binSize}
  >>>

  runtime {
    docker: dockerImage
    disks: 'local-disk ' + ceil(1.1 * size(bam, 'G') + 1) + ' HDD'
    memory: '3G'
    cpu: 1
  }

  output {
    File outBed = '~{outPrefix}_~{outSuffix}.bed'
  }
}

task rescaling {
  input {
    File bam
    File binnedBed
    String outPrefix
    String genomeName

    String dockerImage
  }

  String outBedFile = outPrefix + '_map_scaled.bed'
  String outSnrFile = outPrefix + '_snr.txt'

  command <<<
    /scripts/rescaling/SubmitRescaleBinnedFiles.R \
      --bam_filename '~{bam}' \
      --binned_bed_filename '~{binnedBed}' \
      --genome ~{genomeName} \
      --output_filename '~{outBedFile}' \
      --snr_output_filename '~{outSnrFile}'
  >>>

  runtime {
    docker: dockerImage
    disks: 'local-disk ' + ceil(size(bam, 'G') + 12) + ' HDD'
    memory: '3G'
    cpu: 2
  }

  output {
    File outBed = outBedFile
    Float signalToNoiseRatio = read_float(outSnrFile)
  }
}

task cnv_rescaling {
  input {
    File rescaledBed
    File? cnvRatiosBed
    String outPrefix
    String genomeName
    Boolean bypassCNVRescalingStep

    String dockerImage
  }

  Boolean hasCnvRatios = defined(cnvRatiosBed)
  String outBinnedBedFile = outPrefix + '_binned_final.bed'
  String outCnvRatiosBedFile = outPrefix + '_cnv_ratios.bed'
  String outCnvFlagFile = outPrefix + '_cnv_flag.txt'

  command <<<
    /scripts/cnvRescaling/SubmitCNVRescale.R \
      --binned_bed_filename '~{rescaledBed}' \
      --cnv_rescale_output '~{outBinnedBedFile}' \
      --cnv_ratios_filename '~{if hasCnvRatios then cnvRatiosBed else outCnvRatiosBedFile}' \
      --cnv_flag_output_filename '~{outCnvFlagFile}' \
      --is_input_control ~{if hasCnvRatios then 'F' else 'T'} \
      --assembly ~{genomeName} \
      --bypass_cnv_rescaling_step ~{if bypassCNVRescalingStep then 'T' else 'F'}
  >>>

  runtime {
    docker: dockerImage
    disks: 'local-disk 1 HDD'
    memory: '4G'
    cpu: 1
  }

  output {
    File outBinnedBed = outBinnedBedFile
    File? outCnvRatiosBed = if hasCnvRatios then cnvRatiosBed else outCnvRatiosBedFile
    Boolean cnvsDetected = if bypassCNVRescalingStep then false else read_boolean(outCnvFlagFile)
    Boolean isInputControl = !hasCnvRatios
  }
}

task fitting {
  input {
    File? binnedBed
    String outPrefix

    String dockerImage
  }

  String outParamsFile = outPrefix + '_fit_params.txt'

  command <<<
    /scripts/fitting/SubmitFitDistributionWithCVM.R \
      --binned_bed_filename '~{binnedBed}' \
      --params_output '~{outParamsFile}'
  >>>

  runtime {
    docker: dockerImage
    disks: 'local-disk 1 HDD'
    memory: '1.25G'
    cpu: 1
  }

  output {
    File outParams = outParamsFile
  }
}

task pbs {
  input {
    File? binnedBed
    File fitParams
    String outPrefix

    String dockerImage
  }

  String outBedFile = outPrefix + '_pbs.bed'

  command <<<
    /scripts/pbs/SubmitProbabilityBeingSignal.R \
      --binned_bed_filename '~{binnedBed}' \
      --params_df_filename '~{fitParams}' \
      --pbs_filename '~{outBedFile}'
  >>>

  runtime {
    docker: dockerImage
    disks: 'local-disk 1 HDD'
    memory: '1G'
    cpu: 1
  }

  output {
    File outBed = outBedFile
  }
}

task classifying {
  input {
    File bed
    String genomeName
    String dockerImage
  }
  
  command {
    ulimit -s 65535 #addresses C stack overflow R --vanilla --max-ppsize=500000
    Rscript /scripts/classifying/test.R ${bed} ${genomeName}
  }

  output {
    Array[PredictedEpitope]+ predictedEpitopes = [
      object {
        name: read_string("predict1.txt"),
        probability:  read_float("prob1.txt"),
      },
      object {
        name: read_string("predict2.txt"),
        probability:  read_float("prob2.txt"),
      },
    ]
  }

  runtime {
    preemptible: 3
      docker: dockerImage
      memory: '6.5G'
      cpu: 1
  }
}


task export {
  input {
    File binnedBed
    Float signalToNoiseRatio
    File? cnvRatiosBed
    Boolean cnvsDetected
    Boolean isInputControl
    Boolean bypassCNVRescalingStep
    File fittingParams
    File pbsBed
    Array[PredictedEpitope]+ predictedEpitopes
    String? context

    String outFilesDir
    String outJsonDir
  }

  meta {
    volatile: true
  }

  parameter_meta {
    binnedBed: {
      localization_optional: true
    }
    cnvRatiosBed: {
      localization_optional: true
    }
    fittingParams: {
      localization_optional: true
    }
    pbsBed: {
      localization_optional: true
    }
  }

  Outputs out = object {
    binnedBed: outFilesDir + basename(binnedBed),
    signalToNoiseRatio: signalToNoiseRatio,
    cnvRatiosBed: outFilesDir + basename(select_first([cnvRatiosBed])),
    cnvsDetected: cnvsDetected,
    fittingParams: outFilesDir + basename(fittingParams),
    pbsBed: outFilesDir + basename(pbsBed),
    predictedEpitopes: predictedEpitopes,
    context: context,
  }

  command <<<
    set -e

    gsutil cp '~{binnedBed}' '~{out.binnedBed}'
    if [ "~{isInputControl}" == "true" ] && [ "~{bypassCNVRescalingStep}" == "false" ]; then
      gsutil cp '~{cnvRatiosBed}' '~{out.cnvRatiosBed}'
    fi
    gsutil cp '~{fittingParams}' '~{out.fittingParams}'
    gsutil cp '~{pbsBed}' '~{out.pbsBed}'

    gsutil cp '~{write_json(out)}' '~{outJsonDir}'
  >>>

  runtime {
    docker: 'gcr.io/google.com/cloudsdktool/cloud-sdk:alpine'
    disks: 'local-disk 1 HDD'
    memory: '1G'
  }

  output {
    Outputs outputs = out
  }
}