import json
from google.auth import jwt
from google.cloud import pubsub_v1


def submit_bcl_transfer(project, bcl, workflow_id, sa):
    fname = bcl.split('/')[-1]
    transfers = [
        {
            'destination': 'gs://{0}-bcls/{1}.tar'.format(project, fname),
            'source': bcl,
            'metadata': {'workflow_id': workflow_id}
        }
    ]
    credentials = jwt.Credentials.from_service_account_info(
        sa,
        audience='https://pubsub.googleapis.com/google.pubsub.v1.Publisher'
    )
    publisher = pubsub_v1.PublisherClient(credentials=credentials)
    topic_name = 'projects/{0}/topics/cloudcopy'.format(project)
    request = json.dumps({'transfers': transfers}).encode()
    future = publisher.publish(topic_name, request)
    print(future.result())


sa = json.load(open('keys/broad-epi-dev-1c0cb27e6e12.json'))

# submit_bcl_transfer(
#     'broad-epi-dev',
#     '/seq/epiprod/wine/morgane-test',
#     'workflow-id',
#     sa
# )
submit_bcl_transfer(
    'broad-epi-dev',
    '/seq/test-folder',
    'workflow-id',
    sa
)
