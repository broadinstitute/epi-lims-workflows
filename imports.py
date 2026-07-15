import json
import os
from collections import defaultdict

import requests
from requests.exceptions import HTTPError
from google.cloud import storage as gcs_storage

def chunk_list(lst, chunk_size):
    return [lst[i:i + chunk_size] for i in range(0, len(lst), chunk_size)]

def import_subjects(project, username, password, subject_type, data):
    project = "dev-" if "dev" in project else ""
    params = {
        "method": "import_subjects",
        "subject_type": subject_type,
        "username": username,
        "password": password,
        "json": json.dumps(data),
    }
    try:
        response = requests.get(
            "https://lims.{0}epi.broadinstitute.org/api".format(project),
            params=params,
            headers={"Content-Type": "application/json"},
        )
        print(f"Response: {response}")
    except HTTPError as http_err:
        print(f"HTTP error occurred: {http_err}")
    except Exception as err:
        print(f"Error: {err}")
    else:
        return response.json()


def query_subjects(project, username, password, subject_type, query):
    project = "dev-" if "dev" in project else ""
    params = {
        "method": "subjects",
        "subject_type": subject_type,
        "query": query,
        "limit": "5000",
        "username": username,
        "password": password,
    }
    try:
        response = requests.get(
            "https://lims.{0}epi.broadinstitute.org/api".format(project),
            params=params,
            headers={"Content-Type": "application/json"},
        )
        print(f"Response: {response}")
    except HTTPError as http_err:
        print(f"HTTP error occurred: {http_err}")
    except Exception as err:
        print(f"Error: {err}")
    else:
        return response.json()


def parse_query(response, udf_names):
    result = {}
    for subject in response["Subjects"]:
        udf_values = {}
        for udf in subject["udfs"]:
            if udf["name"] in udf_names:
                if "subject_count" in udf:
                    udf_values[udf["name"]] = udf["subject_count"]
                elif isinstance(udf["value"], dict):
                    udf_values[udf["name"]] = udf["value"]["name"]
                else:
                    udf_values[udf["name"]] = udf["value"]
        result[str(subject["id"])] = udf_values
    return result


def check_subjects(parsed_query, search_udfs):
    matching_subjects = []
    for uid, udfs in parsed_query.items():
        if udfs == search_udfs:
            matching_subjects.append(uid)
    if len(matching_subjects) == 0:
        return {}
    elif len(matching_subjects) > 1:
        subject_names = ', '.join(subject for subject in matching_subjects)
        raise ValueError(f"Multiple existing subjects found: {subject_names}")
    else:
        return {"UID": matching_subjects[0]}


def _copy_gcs_file(src_uri, dst_bucket_name, dst_path):
    client = gcs_storage.Client()
    src_bucket_name, src_blob_name = src_uri[5:].split("/", 1)
    src_bucket = client.bucket(src_bucket_name)
    src_blob = src_bucket.blob(src_blob_name)
    src_bucket.copy_blob(src_blob, client.bucket(dst_bucket_name), dst_path)
    return f"gs://{dst_bucket_name}/{dst_path}"


def _copy_public_gcs_file(src_uri, dst_bucket_name, dst_path):
    _copy_gcs_file(src_uri, dst_bucket_name, dst_path)
    return f"https://storage.googleapis.com/{dst_bucket_name}/{dst_path}"


def _get_projects_set(projects):
    all_projects = []
    for v in projects.values():
        all_projects.extend(v if isinstance(v, list) else [v])
    return sorted(set(all_projects))


def _collect_uids(lims_subjects, import_response, key_field):
    uid_map = {s[key_field]: s["UID"] for s in lims_subjects if "UID" in s}
    new_ids = import_response.get("ids", "").split(",") if import_response.get("ids") else []
    new_names = import_response.get("names", "").split(",") if import_response.get("names") else []
    for name, uid in zip(new_names, new_ids):
        for s in lims_subjects:
            if "UID" not in s and s[key_field] not in uid_map:
                uid_map[s[key_field]] = uid
                break
    return uid_map


def import_lanes(project, username, password, context, outputs):
    lims_lanes = []
    lanes = outputs["laneOutputs"]
    lane_type = "Paired" if lanes[0]["libraryOutputs"][0]["read2"] else "Single"
    # Query for existing lanes
    flowcell = outputs["flowcellId"]
    lims_query = "\"Flow Cell\" = '{}'".format(flowcell)
    udf_names = ["Flow Cell", "Lane-of-FC"]
    query_response = query_subjects(project, username, password, "LIMS_Lane", lims_query)
    print(query_response)
    parsed_response = parse_query(query_response, udf_names)
    for lane_output in outputs["laneOutputs"]:
        lims_lanes.append(
            {
                "Flow Cell": outputs["flowcellId"],
                "Instrument Model": "Illumina " + context["instrumentModel"],
                "Instrument Name": outputs["instrumentId"],
                "Run Registration Date": outputs.get("runDate") or context.get("runDate"),
                "Run End Date": outputs.get("runDate") or context.get("runDate"),
                "Lane-of-FC": str(lane_output["lane"]),
                "Lane Type": lane_type
            }
        )
        search_udfs = {
            "Flow Cell": outputs["flowcellId"],
            "Lane-of-FC": str(lane_output["lane"])
        }
        uid_dict = check_subjects(parsed_response, search_udfs)
        lims_lanes[-1].update(uid_dict)
    uid_names = {str(d['id']): d['name'] for d in query_response['Subjects']}
    search_uids = [d.get('UID', '{}') for d in lims_lanes]
    search_names = ','.join([uid_names.get(uid, '{}') for uid in search_uids])
    import_response = import_subjects(project, username, password, "LIMS_Lane", lims_lanes)
    print(import_response)
    imported_names = (import_response['names'].split(','))
    # imported_names = (
    #     [*import_response['names']] if isinstance(import_response['names'], list) else
    #     [import_response['names']]
    # )
    all_names = search_names.format(*imported_names).split(',')
    return(all_names)

def import_copseqreqs(project, username, password, context, outputs):
    lane_outputs = outputs["laneOutputs"]
    copas = [library_output['name'] for library_output in lane_outputs[0]['libraryOutputs']]
    num_lanes = len(lane_outputs)
    
    seq_tech = context["sequencingTechnology"]
    seq_tech_project = "HiSeq_Mint_ChIP" if seq_tech == "Mint-ChIP" else "HiSeq_ChIP"
    
    # Query for existing CoPSeqReqs
    quoted_copas = ",".join(f"'{copa}'" for copa in copas)
    lims_query = "\"CoPA\"->name = ({})".format(quoted_copas)
    udf_names = ["CoPA"]
    query_response = query_subjects(project, username, password, "CoPSeqReq", lims_query)
    print(query_response)
    parsed_response = parse_query(query_response, udf_names)
    copseqreqs = []
    for copa in copas:
        copseqreqs.append({
            "CoPA": copa,
            "Number of Lanes Requested": num_lanes,
            "Sequencing Center Project": seq_tech_project,
            "Projects": context["projects"].get(copa)
        })
        search_udfs = {
            "CoPA": copa,
        }
        uid_dict = check_subjects(parsed_response, search_udfs)
        copseqreqs[-1].update(uid_dict)
    imported_names = []
    batches = chunk_list(copseqreqs, 10)
    for group in batches:
        import_response = import_subjects(project, username, password, "CoPSeqReq", group)
        print(import_response)
        if import_response['names']:  # Only extend if names is not empty
            imported_names.extend(import_response['names'].split(','))
    uid_names = {str(d['id']): d['name'] for d in query_response['Subjects']}
    search_uids = [d.get('UID', '{}') for d in copseqreqs]
    search_names = ','.join([uid_names.get(uid, '{}') for uid in search_uids])
    all_names = search_names.format(*imported_names).split(',')
    return all_names

def import_lane_subsets(project, username, password, context, outputs, lims_lanes, copseqreqs):
    # Query for existing lanes
    pa_uid = context["poolAliquotUID"]
    read_length = outputs["meanReadLength"]
    projects = context["projects"]
    lims_query = "\"Component of Pooled SeqReq\"->\"CoPA\"->\"Pool Aliquot\"->id = {}".format(pa_uid)
    udf_names = ["Component of Pooled SeqReq", "LIMS_Lane"]
    query_response = query_subjects(project, username, password, "Lane Subset", lims_query)
    print(query_response)
    parsed_response = parse_query(query_response, udf_names)
    for lane_output, lims_lane in zip(outputs["laneOutputs"], lims_lanes):
        lane_subsets = []
        buffer = []
        for library_output, copseqreq in zip(lane_output["libraryOutputs"], copseqreqs):
            coPA = library_output["name"]
            buffer.append({
                "LIMS_Lane": lims_lane,
                "Component of Pooled SeqReq": copseqreq,
                "Reads 1 Filename URI": library_output["read1"],
                "Reads 2 Filename URI": library_output["read2"] or '',
                "Avg Read Length": read_length,
                "% PF Clusters (BC)": library_output["percentPfClusters"],
                "Avg Clusters per Tile (BC)": library_output["meanClustersPerTile"],
                "PF Bases (BC)": library_output["pfBases"],
                "PF Fragments (BC)": library_output["pfFragments"],
                "Projects": projects[coPA]
            })
            search_udfs = {
                "Component of Pooled SeqReq": copseqreq,
                "LIMS_Lane": lims_lane
            }
            uid_dict = check_subjects(parsed_response, search_udfs)
            buffer[-1].update(uid_dict)
            if len(buffer) == 10:
                lane_subsets.append(buffer)
                buffer = []  # Start a new buffer array
        if buffer:
            lane_subsets.append(buffer)
        for group in lane_subsets:
            print(import_subjects(project, username, password, "Lane Subset", group))
    return lane_subsets#import_subjects(project, username, password, "Lane Subset", lane_subsets)

def update_pa(project, username, password, context, outputs):
    pool_aliquots = []
    pool_aliquots.append({
        "UID": context["poolAliquotUID"],
        "HiSeqRun": outputs["runId"],
        "HiSeq Experiment Name": context["experimentName"],
        "HiSeq Folder Name": context["folderName"],
        "M-PF Fragments (BC)/lane": outputs["mPfFragmentsPerLane"],
        "Picard MAX_MISMATCHES": outputs["maxMismatches"],
        "Picard MIN_MISMATCH_DELTA": outputs["minMismatchDelta"],
    })
    return import_subjects(project, username, password, "Pool Aliquot", pool_aliquots)

def import_chipseq_import_outputs(project, username, password, outputs):
    # TODO missing Project information
    print("Importing chip seq import workflow outputs")
    print(outputs)
    print("Parsing context")
    context = json.loads(outputs["context"])
    print(context)
    print(update_pa(project, username, password, context, outputs))
    print("Importing LIMS_Lanes")
    lims_lanes = import_lanes(
        project, username, password, context, outputs
    )
    
    copseqreqs = import_copseqreqs(project, username, password, context, outputs)
    print("Importing Lane Subsets")
    return(import_lane_subsets(
        project, username, password, context, outputs, lims_lanes, copseqreqs
    ))


def import_chipseq_export_outputs(project, username, password, outputs):
    # Do nothing
    pass


def import_alignments(project, username, password, context, outputs):
    genome = outputs["genomeName"]
    ref_seq = f"{genome}_picard"
    alignments = outputs["alignments"]
    pipeline_version = context.get("pipelineVersion")
    projects = context.get("projects", {})
    
    lims_query = " OR ".join(
        f'"Lane Subset"->name = \'{alignment["laneSubsetName"]}\''
        for alignment in alignments
    )
    udf_names = ["Lane Subset", "Reference Sequence"]
    query_response = query_subjects(project, username, password, "Alignment", lims_query)
    print(query_response)
    parsed_response = parse_query(query_response, udf_names)

    lims_alignments = []
    for alignment in alignments:
        lims_alignments.append({
            "Pipeline": "cloud",
            "Pipeline Version": pipeline_version,
            "Aligner": "BWAAlignment",
            "Command Outline": outputs["commandOutlines"]["alignment"],
            "Reference Sequence": ref_seq,
            "Lane Subset": alignment["laneSubsetName"],
            "Read Group": alignment["laneSubsetName"],
            "Aligned Fragments": alignment["alignedFragments"],
            "Duplicate Fragments": alignment["duplicateFragments"],
            "Percent Duplicate Fragments": alignment["percentDuplicateFragments"],
            "ESTIMATED_LIBRARY_SIZE Picard": alignment["estimatedLibrarySize"],
            "Projects": projects.get(alignment["laneSubsetName"], []),
        })
        uid_dict = check_subjects(parsed_response, {
            "Lane Subset": alignment["laneSubsetName"],
            "Reference Sequence": ref_seq,
        })
        lims_alignments[-1].update(uid_dict)

    uid_names = {str(d['id']): d['name'] for d in query_response['Subjects']}
    search_uids = [a.get('UID', '{}') for a in lims_alignments]
    search_names = ','.join([uid_names.get(uid, '{}') for uid in search_uids])
    import_response = import_subjects(project, username, password, "Alignment", lims_alignments)
    print(import_response)
    imported_names = import_response['names'].split(',')
    alignment_names = search_names.format(*imported_names).split(',')

    lane_alns_bucket = f"{project}-lane-alns"
    uid_map = _collect_uids(lims_alignments, import_response, "Lane Subset")
    alignment_updates = []
    for name, alignment in zip(alignment_names, alignments):
        uid = uid_map.get(alignment["laneSubsetName"])
        id = f"{int(name.split()[-1]):06d}"
        bam_uri = _copy_gcs_file(alignment["bam"], lane_alns_bucket, f"lane_aln_{id}.bam")
        _copy_gcs_file(alignment["bai"], lane_alns_bucket, f"lane_aln_{id}.bai")
        alignment_updates.append({"UID": uid, "BAM Filename URI": bam_uri})

    print(import_subjects(project, username, password, "Alignment", alignment_updates))
    return alignment_names

def import_app(project, username, password, context, outputs, alignment_names):
    genome = outputs["genomeName"]
    ref_seq = f"{genome}_picard"
    app = outputs["alignmentPostProcessing"]
    pipeline_version = context.get("pipelineVersion")
    projects_set = _get_projects_set(context.get("projects", {}))
    predicted_epitopes = app.get("predictedEpitopes")

    input_alignments = ";".join(alignment_names)
    read_groups = ",".join(a["laneSubsetName"] for a in outputs["alignments"])

    agg = context.get("aggregation")
    if genome == "hg19" and agg and agg.get("type") == "Pool_Component":
        library_name = outputs["alignments"][0]["libraryName"]
        aggregation_type = json.dumps(["Pool Component", "Library"])
        aggregation_value = json.dumps([agg["name"], library_name])
    else:
        aggregation_type = "NA"
        aggregation_value = "NA"
    
    lims_query = " AND ".join(
        f'"Input_Alignments_SL" = \'{alignment}\''
        for alignment in alignment_names
    )
    udf_names = ["Input Alignments"]
    query_response = query_subjects(project, username, password, "Alignment Post Processing", lims_query)
    print(query_response)
    parsed_response = parse_query(query_response, udf_names)

    app_subject = {
        "Pipeline": "cloud",
        "Pipeline Version": pipeline_version,
        "Processing Type": "pool alignments",
        "Aggregation Type": aggregation_type,
        "Aggregation Value": aggregation_value,
        "PicardTools Version": outputs["softwareVersions"]["picard"],
        "SAMTools Version": outputs["softwareVersions"]["samtools"],
        "Command Outline": outputs["commandOutlines"]["alignmentPostProcessing"],
        "Reference Sequence": ref_seq,
        "Input Alignments": input_alignments,
        "Input_Alignments_SL": alignment_names,
        "Input Subjects": input_alignments,
        "Read Groups": read_groups,
        "Species Common Name": context.get("speciesCommonName"),
        "Cell Types": context.get("cellTypes"),
        "Epitopes": context.get("epitopes"),
        "Total Fragments": app["totalFragments"],
        "Aligned Fragments": app["alignedFragments"],
        "Duplicate Fragments": app["duplicateFragments"],
        "Percent Duplicate Fragments": app["percentDuplicateFragments"],
        "ESTIMATED_LIBRARY_SIZE Picard": app["estimatedLibrarySize"],
        "Mitochondrial reads": app["percentMito"],
        "Vplot Score": app.get("vplotScore"),
        "Projects": projects_set,
    }
    if predicted_epitopes:
        app_subject["RF Top predicted epitope"] = predicted_epitopes[0]["name"]
        app_subject["RF Top epitope prediction probability"] = predicted_epitopes[0]["probability"]
        app_subject["RF Second predicted epitope"] = predicted_epitopes[1]["name"]
        app_subject["RF Second epitope prediction probability"] = predicted_epitopes[1]["probability"]

    uid_dict = check_subjects(parsed_response, {"Input Alignments": input_alignments})
    app_subject.update(uid_dict)

    uid_names = {str(d['id']): d['name'] for d in query_response['Subjects']}
    search_uid = app_subject.get('UID', '{}')
    search_name = uid_names.get(search_uid, '{}')
    import_response = import_subjects(project, username, password, "Alignment Post Processing", [app_subject])
    print(import_response)
    imported_names = import_response['names'].split(',')
    app_name = search_name.format(*imported_names) if '{}' in str(search_name) else search_name

    existing_uid = app_subject.get("UID")
    new_ids = import_response.get("ids", "").split(",") if import_response.get("ids") else []
    app_uid = existing_uid or (new_ids[0] if new_ids else None)

    agg_alns_bucket = f"{project}-aggregated-alns"
    reports_bucket = f"{project}-reports"

    id = f"{int(app_name.split()[-1]):06d}"
    bam_uri = _copy_gcs_file(app["bam"], agg_alns_bucket, f"aggregated_aln_{id}.bam")      
    _copy_gcs_file(app["bai"], agg_alns_bucket, f"aggregated_aln_{id}.bai")

    app_update = {"UID": app_uid, "BAM_Filename_URI": bam_uri}

    if app.get("fingerprintFile"):
        app_update["Genotyping Fingerprint URI"] = _copy_gcs_file(
            app["fingerprintFile"], agg_alns_bucket, f"aggregated_aln_{id}.fingerprint.bam")
        app_update["Genotyping Fingerprint Self LOD"] = app.get("fingerprintSelfLOD")

    if app.get("insertSizeHistogram"):
        app_update["InsertSizeMetrics"] = _copy_public_gcs_file(
            app["insertSizeHistogram"], reports_bucket, f"aggregated_aln_{id}.histogram.pdf")

    if app.get("vplot"):
        app_update["Vplot"] = _copy_public_gcs_file(
            app["vplot"], reports_bucket, f"aggregated_aln_{id}.vplot.png")

    print(import_subjects(project, username, password, "Alignment Post Processing", [app_update]))
    return app_name

def import_segmentations(project, username, password, context, outputs, app_name):
    segmentations = outputs["segmentations"]
    pipeline_version = context.get("pipelineVersion")
    projects_set = _get_projects_set(context.get("projects", {}))

    lims_query = "\"Alignment Post Processing\"->name = '{}'".format(app_name)
    udf_names = ["Alignment Post Processing", "Segmenter"]
    query_response = query_subjects(project, username, password, "Segmentation", lims_query)
    print(query_response)
    parsed_response = parse_query(query_response, udf_names)

    lims_segs = []
    for seg in segmentations:
        lims_segs.append({
            "Pipeline Version": pipeline_version,
            "Segmenter": seg["peakStyle"],
            "Segmenter Version": outputs["softwareVersions"]["homer"],
            "Alignment Post Processing": app_name,
            "Number of Segments": seg["segmentCount"],
            "SPOT": seg["spot"],
            "Projects": projects_set,
        })
        uid_dict = check_subjects(parsed_response, {
            "Alignment Post Processing": app_name,
            "Segmenter": seg["peakStyle"],
        })
        lims_segs[-1].update(uid_dict)

    uid_names = {str(d['id']): d['name'] for d in query_response['Subjects']}
    search_uids = [s.get('UID', '{}') for s in lims_segs]
    search_names = ','.join([uid_names.get(uid, '{}') for uid in search_uids])
    import_response = import_subjects(project, username, password, "Segmentation", lims_segs)
    print(import_response)
    imported_names = import_response['names'].split(',')
    seg_names = search_names.format(*imported_names).split(',')

    segs_bucket = f"{project}-segmentations"
    uid_map = _collect_uids(lims_segs, import_response, "Segmenter")
    seg_updates = []
    for name, seg in zip(seg_names, segmentations):
        uid = uid_map.get(seg["peakStyle"])
        id = f"{int(name.split()[-1]):06d}"
        bed_uri = _copy_gcs_file(seg["bed"], segs_bucket, f"segmentation_{id}.bed")
        seg_updates.append({"UID": uid, "BED Filename URI": bed_uri})

    print(import_subjects(project, username, password, "Segmentation", seg_updates))

def import_track(project, username, password, context, outputs, app_name):
    track = outputs["track"]
    genome = outputs["genomeName"]
    pipeline_version = context.get("pipelineVersion")
    projects_set = _get_projects_set(context.get("projects", {}))
    agg = context.get("aggregation")

    lims_query = "\"Alignment Post Processing\"->name = '{}'".format(app_name)
    udf_names = ["Alignment Post Processing"]
    query_response = query_subjects(project, username, password, "Track", lims_query)
    print(query_response)
    parsed_response = parse_query(query_response, udf_names)

    track_subject = {
        "Pipeline Version": pipeline_version,
        "IGVTools Version": outputs["softwareVersions"]["igv"],
        "WigToBigWig Version": outputs["softwareVersions"]["wigToBigWig"],
        "Command Outline": outputs["commandOutlines"]["track"],
        "Alignment Post Processing": app_name,
        "Projects": projects_set,
    }
    uid_dict = check_subjects(parsed_response, {"Alignment Post Processing": app_name})
    track_subject.update(uid_dict)

    uid_names = {str(d['id']): d['name'] for d in query_response['Subjects']}
    search_uid = track_subject.get('UID', '{}')
    search_name = uid_names.get(search_uid, '{}')
    import_response = import_subjects(project, username, password, "Track", [track_subject])
    print(import_response)
    imported_names = import_response['names'].split(',')
    track_name = search_name.format(*imported_names) if '{}' in str(search_name) else search_name

    existing_uid = track_subject.get("UID")
    new_ids = import_response.get("ids", "").split(",") if import_response.get("ids") else []
    track_uid = existing_uid or (new_ids[0] if new_ids else None)

    tracks_bucket = f"{project}-tracks"
    id = f"{int(track_name.split()[-1]):06d}"
    bw_uri = _copy_gcs_file(track["bigWig"], tracks_bucket, f"track_{id}.bw")
    tdf_uri = _copy_gcs_file(track["tdf"], tracks_bucket, f"track_{id}.tdf")

    print(import_subjects(project, username, password, "Track", [{
        "UID": track_uid, 
        "BigWig Filename URI": bw_uri, 
        "TDF Filename URI": tdf_uri
    }]))

    if genome in ["hg19", "mm10"] and agg:
        print(import_subjects(project, username, password, agg["type"], [
            {"UID": str(agg["uid"]), "Track": track_name}
        ]))

def import_chipseq_outputs(project, username, password, outputs):
    print("Importing chip-seq workflow outputs")
    print(outputs)
    print("Parsing context")
    context = json.loads(outputs["context"])
    alignment_names = import_alignments(project, username, password, context, outputs)
    app_name = import_app(project, username, password, context, outputs, alignment_names)
    import_segmentations(project, username, password, context, outputs, app_name)
    import_track(project, username, password, context, outputs, app_name)
    # TODO: auto-launch CNV workflow when app_info["epitopes"] == "WCE"


def import_cnv_outputs(project, username, password, outputs):
    context = json.loads(outputs["context"])
    predicted_epitopes = outputs.get("predictedEpitopes")
    app_update = {
        "UID": context["uid"],
        "Input Control": context.get("inputControlName"),
        "SNR": outputs.get("signalToNoiseRatio"),
        "CNV Binned BED URI": outputs.get("binnedBed"),
        "CNV Ratios BED URI": outputs.get("cnvRatiosBed"),
        "CNVs Detected": "Yes" if outputs.get("cnvsDetected") else "No",
        "Fitting Parameters URI": outputs.get("fittingParams"),
        "PBS BED URI": outputs.get("pbsBed"),
    }
    if predicted_epitopes:
        app_update["CNV Top predicted epitope"] = predicted_epitopes[0]["name"]
        app_update["CNV Top epitope prediction probability"] = predicted_epitopes[0]["probability"]
        app_update["CNV Second predicted epitope"] = predicted_epitopes[1]["name"]
        app_update["CNV Second epitope prediction probability"] = predicted_epitopes[1]["probability"]
    print(import_subjects(project, username, password, "Alignment Post Processing", [app_update]))


def import_ss_lane_subsets(project, username, password, context, outputs, lims_lanes):
    # Query for existing lanes
    pa_uid = context["poolAliquotUID"]
    lims_query = "\"SS-CoPA\"->\"SS-PA\"->id = {}".format(pa_uid)
    udf_names = ["SS-CoPA", "LIMS_Lane"]
    query_response = query_subjects(project, username, password, "SS-LS", lims_query)
    print(query_response)
    parsed_response = parse_query(query_response, udf_names)
    for lane_output, lims_lane in zip(outputs["laneOutputs"], lims_lanes):
        lane_subsets = []
        buffer = []
        for library_output in lane_output["libraryOutputs"]:
            buffer.append({
                "LIMS_Lane": lims_lane,
                "Reads 1 Filename URI": library_output["read1"],
                "Reads 2 Filename URI": library_output["read2"] or '',
                "SS-CoPA": library_output["name"],
                "% PF Clusters (BC)": library_output["percentPfClusters"],
                "Avg Clusters per Tile (BC)": library_output["meanClustersPerTile"],
                "PF Bases (BC)": library_output["pfBases"],
                "PF Fragments (BC)": library_output["pfFragments"],
                "DEMUX Version": outputs["pipelineVersion"]
            })
            search_udfs = {
                "SS-CoPA": library_output["name"],
                "LIMS_Lane": lims_lane
            }
            uid_dict = check_subjects(parsed_response, search_udfs)
            buffer[-1].update(uid_dict)
            if len(buffer) == 10:
                lane_subsets.append(buffer)
                buffer = []  # Start a new buffer array
        if buffer:
            lane_subsets.append(buffer)
        for group in lane_subsets:
            print(import_subjects(project, username, password, "SS-LS", group))
    return lane_subsets#import_subjects(project, username, password, "SS-LS", lane_subsets)

def update_ss_pa(project, username, password, context, outputs):
    # Update SS-PA with R1 and R2 lengths
    # TODO single end runs
    pool_aliquots = []
    pool_aliquots.append({
        "UID": context["poolAliquotUID"],
        "Read1_Length": outputs["r1Length"],
        "Read2_Length": outputs["r2Length"]
    })
    return import_subjects(project, username, password, "SS-PA", pool_aliquots)

def import_shareseq_import_outputs(project, username, password, outputs):
    # TODO missing Project information
    print("Importing share seq import workflow outputs")
    print(outputs)
    print("Parsing context")
    context = json.loads(outputs["context"])
    print(context)

    print(update_ss_pa(project, username, password, context, outputs))

    print("Importing LIMS_Lanes")
    lims_lanes = import_lanes(
        project, username, password, context, outputs
    )

    print("Importing SS-Lane Subsets")
    import_ss_lane_subsets(
        project, username, password, context, outputs, lims_lanes
    )


def import_shareseq_proto_outputs(project, username, password, outputs):
    # Do nothing
    pass


def update_10x_pa(project, username, password, context, outputs):
    # Update 10X-PA with R1, R2, I1, I2 lengths
    pool_aliquots = []
    pool_aliquots.append({
        "UID": context["poolAliquotUID"],
        "Read1_Length": outputs["r1Length"],
        "Read2_Length": outputs["r2Length"],
        "Index1_i7_Length": outputs["i1Length"],
        "Index2_i5_Length": outputs["i2Length"],
    })
    return import_subjects(project, username, password, "10X-PA", pool_aliquots)

def reshape_10x_fastqs(outputs):
    for lane in outputs.get("laneOutputs", []):
        fastqs = lane.get("fastqs", [])
        library_dict = defaultdict(dict)
        
        for path in fastqs:
            filename = os.path.basename(path)
            
            number = filename.split('_')[0].replace("10X-CoPA-", "")
            library_name = f"10X-CoPA {number}"
            
            # Identify read type
            if "_R1_" in filename:
                library_dict[library_name]["read1"] = path
            elif "_R2_" in filename:
                library_dict[library_name]["read2"] = path
            elif "_I1_" in filename:
                library_dict[library_name]["index1"] = path
            elif "_I2_" in filename:
                library_dict[library_name]["index2"] = path
            else:
                raise ValueError(f"Unrecognized FASTQ filename: {filename}")
            
            # Always set the name
            library_dict[library_name]["name"] = library_name
        
        # Replace fastqs with libraryOutputs
        lane["libraryOutputs"] = list(library_dict.values())
        lane.pop("fastqs", None)  # remove original fastqs if present
    
    return outputs

def import_10x_lane_subsets(project, username, password, context, outputs, lims_lanes):
    # Query for existing lanes
    pa_uid = context["poolAliquotUID"]
    lims_query = "\"10X-CoPA\"->\"10X-PA\"->id = {}".format(pa_uid)
    udf_names = ["10X-CoPA", "LIMS_Lane"]
    query_response = query_subjects(project, username, password, "10X-LS", lims_query)
    print(query_response)
    parsed_response = parse_query(query_response, udf_names)
    for lane_output, lims_lane in zip(outputs["laneOutputs"], lims_lanes):
        lane_subsets = []
        buffer = []
        for library_output in lane_output["libraryOutputs"]:
            buffer.append({
                "LIMS_Lane": lims_lane,
                "Reads 1 Filename URI": library_output["read1"],
                "Reads 2 Filename URI": library_output.get("read2", ''),
                "Index 1 Filename URI": library_output.get("index1", ''),
                "Index 2 Filename URI": library_output.get("index2", ''),
                "10X-CoPA": library_output["name"],
                # "% PF Clusters (BC)": library_output["percentPfClusters"],
                # "Avg Clusters per Tile (BC)": library_output["meanClustersPerTile"],
                # "PF Bases (BC)": library_output["pfBases"],
                # "PF Fragments (BC)": library_output["pfFragments"],
                "DEMUX Version": outputs["pipelineVersion"]
            })
            search_udfs = {
                "10X-CoPA": library_output["name"],
                "LIMS_Lane": lims_lane
            }
            uid_dict = check_subjects(parsed_response, search_udfs)
            buffer[-1].update(uid_dict)
            if len(buffer) == 10:
                lane_subsets.append(buffer)
                buffer = []  # Start a new buffer array
        if buffer:
            lane_subsets.append(buffer)
        for group in lane_subsets:
            print(import_subjects(project, username, password, "10X-LS", group))
    return lane_subsets#import_subjects(project, username, password, "SS-LS", lane_subsets)

def import_10x_import_outputs(project, username, password, outputs):
    print("Importing 10x import workflow outputs")
    print(outputs)
    print("Parsing context")
    context = json.loads(outputs["context"])
    print(context)

    print(update_10x_pa(project, username, password, context, outputs))

    print("Importing LIMS_Lanes")
    reshape_10x_fastqs(outputs)
    lims_lanes = import_lanes(
        project, username, password, context, outputs
    )
        
    print("Importing 10X-Lane Subsets")
    import_10x_lane_subsets(
        project, username, password, context, outputs, lims_lanes
    )
