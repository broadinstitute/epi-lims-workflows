import sys
import json
import requests
from requests.exceptions import HTTPError

username = 'lims-api-user'
password = sys.argv[1]
url = 'https://lims.dev-epi.broadinstitute.org/api'


def get_token():
    response = requests.post(
        url,
        params={
            'method': 'gen_token',
            'username': username,
            'password': password
        },
        headers={
            'Content-Type': 'application/json'
        }
    )
    return response.json()['auth_token']


def query_lims(json_data):
    params = {
        'method': 'subjects',
        'username': username,
        'password': password
        # You can also use a refresh token, but don't need to
        # 'auth_token': get_token()
    }
    try:
        response = requests.get(
            url,
            params={**params, **json_data},
            headers={
                'Content-Type': 'application/json'
            }
        )
    except HTTPError as http_err:
        print(f'HTTP error occurred: {http_err}')
    except Exception as err:
        print(f'Error: {err}')
    else:
        print('Success!')
        print(response.json())


def import_subjects(subject_type, data):
    params = {
        'method': 'import_subjects',
        'subject_type': subject_type,
        'username': username,
        'password': password,
        'json': json.dumps(data)
    }
    try:
        response = requests.get(
            url,
            params=params,
            headers={
                'Content-Type': 'application/json'
            }
        )
    except HTTPError as http_err:
        print(f'HTTP error occurred: {http_err}')
    except Exception as err:
        print(f'Error: {err}')
    else:
        print('Success!')
        print(response.json())
        return response.json()


# query_lims({
#     'subject_type': 'Alignment Post Processing',
#     'subject_ids': [385028]
# })

# import_subjects('Alignment Post Processing', [{
#     'SNR': 1.0
# }, {
#     'SNR': 2.0
# }])

# Simulate importing ChIP-Seq outputs
outputs = json.loads(open('chipseq_outputs.json', 'r').read())

genome = outputs['genomeName']
commands = outputs['commandOutlines']
software = outputs['softwareVersions']

ref_seq = '{0}_picard'.format(genome)

# Import Alignments
alignments = []
for alignment in outputs['alignments']:
    alignments.append({
        # TODO - from context
        # 'Pipeline': cloudPipeline,
        # 'Pipeline Version': pipelineVersion,
        'Aligner': 'BWAAlignment',
        'Command Outline': commands['alignment'],
        'Reference Sequence': ref_seq,
        'Lane Subset': alignment['laneSubsetName'],
        'Read Group': alignment['laneSubsetName'],
        'Aligned Fragments': alignment['alignedFragments'],
        'Duplicate Fragments': alignment['duplicateFragments'],
        'Percent Duplicate Fragments': alignment['percentDuplicateFragments'],
        'ESTIMATED_LIBRARY_SIZE Picard': alignment['estimatedLibrarySize']
    })
alignment_response = import_subjects('Alignment', alignments)

input_alignments = alignment_response['names']
read_groups = ','.join(map(lambda a: a['laneSubsetName'],
                       outputs['alignments']))

# Import APP
app = outputs['alignmentPostProcessing']
app_response = import_subjects('Alignment Post Processing', {
    # TODO - from context
    # 'Pipeline': cloudPipeline,
    # 'Pipeline_Version': pipelineVersion,
    'Processing Type': 'pool alignments',
    # TODO - from context
    # 'Aggregation Type': poolComponentName ? stringify(['Pool Component', 'Library']): 'NA',
    # 'Aggregation Value': poolComponentName ? stringify([poolComponentName, libraryName]): 'NA',
    'PicardTools Version': software['picard'],
    'SAMTools Version': software['samtools'],
    'Command Outline': commands['alignmentPostProcessing'],
    'Reference Sequence': ref_seq,
    'Input Alignments': input_alignments,
    'Input_Alignments_SL': input_alignments.replace(',', ';'),
    'Input Subjects': input_alignments,
    'Read Groups': read_groups,
    # 'Species Common Name': speciesCommonName, # TODO from context
    # Cell_Types: cellTypes, # TODO from context
    # Epitopes: epitopes,    # TODO from context
    'Total Fragments': app['totalFragments'],
    'Aligned Fragments': app['alignedFragments'],
    'Duplicate Fragments': app['duplicateFragments'],
    'Percent Duplicate Fragments': app['percentDuplicateFragments'],
    'ESTIMATED_LIBRARY_SIZE Picard': app['estimatedLibrarySize'],
    'RF Top predicted epitope': app['predictedEpitopes'][0]['name'],
    'RF Top epitope prediction_probability': app['predictedEpitopes'][0]['probability'],
    'RF Second predicted epitope': app['predictedEpitopes'][1]['name'],
    'RF Second epitope prediction_probability': app['predictedEpitopes'][1]['probability'],
    'Mitochondrial reads': app['percentMito'],
    'Vplot Score': app['vplotScore'],
    # Projects: projectsSet,
})

app_name = app_response['names']

# Import Segmentations
segmentations = []
for segmentation in outputs['segmentations']:
    segmentations.append({
        # 'Pipeline_Version': pipelineVersion,
        'Segmenter': segmentation['peakStyle'],
        'Segmenter Version': software['homer'],
        'Alignment Post Processing': app_name,
        'Number of Segments': segmentation['segmentCount'],
        'SPOT': segmentation['spot'],
        # 'Projects': projectsSet,
    })
segmentation_response = import_subjects('Segmentation', segmentations)

# Import Track
track = outputs['track']
track_response = import_subjects('Track', {
    # 'Pipeline Version': pipelineVersion,
    'IGVTools Version': software['igv'],
    'WigToBigWig Version': software['wigToBigWig'],
    'Command Outline': commands['track'],
    'Alignment Post Processing': app_name,
    # 'Projects': projectsSet,
})
