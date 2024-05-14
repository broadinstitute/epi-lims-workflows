import json
import requests
from requests.exceptions import HTTPError


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
                if isinstance(udf["value"], dict):
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


def import_alignments(project, username, password, alignments, ref_seq, commands):
    lims_alignments = []
    for alignment in alignments:
        lims_alignments.append(
            {
                # TODO - from context
                # 'Pipeline': cloudPipeline,
                # 'Pipeline Version': pipelineVersion,
                "Aligner": "BWAAlignment",
                "Command Outline": commands["alignment"],
                "Reference Sequence": ref_seq,
                "Lane Subset": alignment["laneSubsetName"],
                "Read Group": alignment["laneSubsetName"],
                "Aligned Fragments": alignment["alignedFragments"],
                "Duplicate Fragments": alignment["duplicateFragments"],
                "Percent Duplicate Fragments": alignment["percentDuplicateFragments"],
                "ESTIMATED_LIBRARY_SIZE Picard": alignment["estimatedLibrarySize"],
            }
        )
    return import_subjects(project, username, password, "Alignment", lims_alignments)


def import_app(
    project,
    username,
    password,
    app,
    alignments,
    lane_subsets,
    ref_seq,
    software,
    commands,
):
    return import_subjects(
        project,
        username,
        password,
        "Alignment Post Processing",
        {
            # TODO - from context
            # 'Pipeline': cloudPipeline,
            # 'Pipeline_Version': pipelineVersion,
            "Processing Type": "pool alignments",
            # TODO - from context
            # 'Aggregation Type': poolComponentName ? stringify(['Pool Component', 'Library']): 'NA',
            # 'Aggregation Value': poolComponentName ? stringify([poolComponentName, libraryName]): 'NA',
            "PicardTools Version": software["picard"],
            "SAMTools Version": software["samtools"],
            "Command Outline": commands["alignmentPostProcessing"],
            "Reference Sequence": ref_seq,
            "Input Alignments": alignments,
            "Input_Alignments_SL": alignments.replace(",", ";"),
            "Input Subjects": alignments,
            "Read Groups": lane_subsets,
            # 'Species Common Name': speciesCommonName, # TODO from context
            # Cell_Types: cellTypes, # TODO from context
            # Epitopes: epitopes,    # TODO from context
            "Total Fragments": app["totalFragments"],
            "Aligned Fragments": app["alignedFragments"],
            "Duplicate Fragments": app["duplicateFragments"],
            "Percent Duplicate Fragments": app["percentDuplicateFragments"],
            "ESTIMATED_LIBRARY_SIZE Picard": app["estimatedLibrarySize"],
            "RF Top predicted epitope": app["predictedEpitopes"][0]["name"],
            "RF Top epitope prediction_probability": app["predictedEpitopes"][0][
                "probability"
            ],
            "RF Second predicted epitope": app["predictedEpitopes"][1]["name"],
            "RF Second epitope prediction_probability": app["predictedEpitopes"][1][
                "probability"
            ],
            "Mitochondrial reads": app["percentMito"],
            "Vplot Score": app["vplotScore"],
            # Projects: projectsSet,
        },
    )


def import_segmentations(
    project, username, password, segmentations, app_name, software
):
    lims_segmentations = []
    for segmentation in segmentations:
        lims_segmentations.append(
            {
                # 'Pipeline_Version': pipelineVersion,
                "Segmenter": segmentation["peakStyle"],
                "Segmenter Version": software["homer"],
                "Alignment Post Processing": app_name,
                "Number of Segments": segmentation["segmentCount"],
                "SPOT": segmentation["spot"],
                # 'Projects': projectsSet,
            }
        )
    return import_subjects(project, username, password, "Segmentation", lims_segmentations)


def import_track(project, username, password, track, app_name, software, commands):
    return import_subjects(
        project,
        username,
        password,
        "Track",
        {
            # 'Pipeline Version': pipelineVersion,
            "IGVTools Version": software["igv"],
            "WigToBigWig Version": software["wigToBigWig"],
            "Command Outline": commands["track"],
            "Alignment Post Processing": app_name,
            # 'Projects': projectsSet,
        },
    )

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
                "Run Registration Date": outputs["runDate"],
                "Run End Date": outputs["runDate"],
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
    
def import_bcl_outputs(project, username, password, outputs):
    # Import Lanes, CopSeqReqs, LaneSubsets
    # Can likely use import_lanes above for this function
    # Update Pool Aliquot
    # Launch ChipSeq workflow? 
    pass


def import_shareseq_import_outputs(project, username, password, outputs):
    # TODO missing Project information
    print("importing share seq import workflow outputs")
    print(outputs)
    print("parsing context")
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

def import_chipseq_outputs(project, username, password, outputs):
    # Parse Cromwell job outputs
    genome = outputs["genomeName"]
    commands = outputs["commandOutlines"]
    software = outputs["softwareVersions"]
    ref_seq = "{0}_picard".format(genome)

    # Import Alignments into LIMS
    print("Importing Alignments")
    lims_alignments = import_alignments(
        project, username, password, outputs["alignments"], ref_seq, commands
    )

    # Import APP into LIMS
    print("Importing APP")
    input_alignments = lims_alignments["names"]
    read_groups = ",".join(map(lambda a: a["laneSubsetName"], outputs["alignments"]))
    lims_app = import_app(
        project,
        username,
        password,
        outputs["alignmentPostProcessing"],
        input_alignments,
        read_groups,
        ref_seq,
        software,
        commands,
    )

    # Import Segmentations into LIMS
    print("Importing Segmentations")
    app_name = lims_app["names"]
    import_segmentations(
        project, username, password, outputs["segmentations"], app_name, software
    )

    # Import Track into LIMS
    print("Importing Track")
    import_track(
        project, username, password, outputs["track"], app_name, software, commands
    )

    # TODO Copy files to buckets
    # TODO Launch CNV for WCEs


def import_cnv_outputs(project, username, password, outputs):
    pass
