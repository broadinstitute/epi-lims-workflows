# Deploy VPC, Serverless VPC connector, and NAT gateway.
# These allow on-workflow-done GCF to communicate with AWS via
# a static IP address that is whitelisted in the AWS ALB secgroup.

# TODO these commands were tested by running them once to create
# the resources. Resource creation should be automated. Many of
# these commands will produce an error - "already exists" - if
# run again, so we need to figure out a way to gracefully manage
# state in the cloudbuild deploy script, or use a system built
# for this purpose like Terraform. Could also use a bunch of "if"
# statements in the deploy script but this will add some time 
# since need to do 2 calls (gcloud list and create).

PROJECT=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects list --filter="project_id:$PROJECT" --format='value(project_number)')
REGION="us-east1"

# VPC
gcloud compute networks create workflow-vpc \
    --subnet-mode=custom \
    --bgp-routing-mode=regional

# Serverless VPC connector to enable communication between cloud function and VPC
gcloud compute networks vpc-access connectors create workflow-vpc-connector \
    --network workflow-vpc \
    --region $REGION \
    --range 10.8.0.0/28

gcloud projects add-iam-policy-binding $PROJECT \
  --member=serviceAccount:service-$PROJECT_NUMBER@gcf-admin-robot.iam.gserviceaccount.com \
  --role=roles/viewer

gcloud projects add-iam-policy-binding $PROJECT \
  --member=serviceAccount:service-$PROJECT_NUMBER@gcf-admin-robot.iam.gserviceaccount.com \
  --role=roles/compute.networkUser

# Reserve an IP address for NAT gateway
# Need to check for existence because 
if [ -z "$(gcloud compute addresses list | grep workflow-static-ip)" ]; then
  gcloud compute addresses create workflow-static-ip --region=$REGION
else
  echo "Static IP for on-workflow-done NAT gateway already exists"
fi

# Router for NAT gateway
gcloud compute routers create workflow-router \
    --network workflow-vpc \
    --region $REGION

# NAT configuration 
gcloud compute routers nats create workflow-nat-config \
    --router=workflow-router \
    --nat-external-ip-pool=workflow-static-ip \
    --nat-all-subnet-ip-ranges \
    --router-region=$REGION \
    --enable-logging
