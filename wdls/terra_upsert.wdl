version 1.0

workflow TerraUpsert {
	input {
		File tsv
		String terra_project
		String workspace_name
		String dockerImage = "us.gcr.io/buenrostro-share-seq/share_task_preprocess"
	}
	
}

task Upsert {
	input {
		File tsv
		String terra_project
		String workspace_name
		String dockerImage
	}
	
	command <<<
		python3 /software/flexible_import_entities_standard.py \
			-t "~{tsv}" \
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