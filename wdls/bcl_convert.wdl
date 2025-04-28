version 1.0
workflow BclConvertWorkflow {
    
    input {
        File bcl_tar_gcs         # GCS path to tar.gz of BCLs
        File sample_sheet      # Local path or cloud path to sample sheet
    }

    call BclConvert {
        input:
            bcl_tar_gcs=bcl_tar_gcs,
            sample_sheet=sample_sheet        
    }

    output {
        Array[File] fastq_files = BclConvert.fastq_files
    }
}

task BclConvert {
    input {
        File bcl_tar_gcs
        File sample_sheet
	#Boolean zipped = true

	# GCS folder where to store the output data
	#String outputDir
    }

    #String tar_flags = if zipped then 'ixzf' else 'ixf'
    String tar_flags = 'ixf'
    String untarBcl = 'gsutil -m -o GSUtil:parallel_thread_count=1' +
		                ' -o GSUtil:sliced_object_download_max_components=8' +
		                ' cp "~{bcl_tar_gcs}" . && ' +
		                'tar "~{tar_flags}" "~{basename(bcl_tar_gcs)}" --exclude Images --exclude Thumbnail_Images' 
    Float bclSize = size(bcl_tar_gcs, 'G')
    Int diskSize = ceil(6.1 * bclSize)
    String diskType = if diskSize > 375 then "SSD" else "LOCAL"

    command <<<
        ls
        echo "Downloading BCL tarball from:" ~{bcl_tar_gcs}
        ~{untarBcl}
        ls
        echo "Running bcl-convert..."
        bcl-convert \
            --bcl-input-directory . \
            --output-directory fastq \
            --sample-sheet ~{sample_sheet}
    >>>

    output {
        Array[File] fastq_files = glob("fastq/*fastq.gz")
    }

    runtime {
        docker: "nchernia/bcl-convert:latest"
        cpu: 16
        memory: "64G"
        disks: "local-disk ~{diskSize} ~{diskType}"
    }
}
