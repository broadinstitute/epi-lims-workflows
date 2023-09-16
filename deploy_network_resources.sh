# TODO TEST THAT DOESN'T CREATE DUPLICATE RESOURCES ON SECOND DEPLOY

#### launch-cromwell

# reserve static IP
gcloud compute addresses create lims-cromwell-ip --project=broad-epi --region=us-east1

# REST requests for load balancer configuration + deploy
# POST https://compute.googleapis.com/compute/v1/projects/broad-epi/global/securityPolicies
# {
#   "description": "Default security policy for: lims-cromwell-launcher-lb-backend",
#   "name": "default-security-policy-backend-service-lims-cromwell-launcher",
#   "rules": [
#     {
#       "action": "allow",
#       "match": {
#         "config": {
#           "srcIpRanges": [
#             "*"
#           ]
#         },
#         "versionedExpr": "SRC_IPS_V1"
#       },
#       "priority": 2147483647
#     },
#     {
#       "action": "throttle",
#       "description": "Default rate limiting rule",
#       "match": {
#         "config": {
#           "srcIpRanges": [
#             "*"
#           ]
#         },
#         "versionedExpr": "SRC_IPS_V1"
#       },
#       "priority": 2147483646,
#       "rateLimitOptions": {
#         "conformAction": "allow",
#         "enforceOnKey": "IP",
#         "exceedAction": "deny(403)",
#         "rateLimitThreshold": {
#           "count": 500,
#           "intervalSec": 60
#         }
#       }
#     }
#   ]
# }

# POST https://dev-compute.sandbox.googleapis.com/compute/beta/projects/broad-epi/regions/us-east1/networkEndpointGroups
# {
#   "cloudRun": {
#     "service": "cromwell-launcher"
#   },
#   "name": "lims-cromwell-launcher-lb-endpoint-group",
#   "networkEndpointType": "SERVERLESS",
#   "region": "projects/broad-epi/regions/us-east1"
# }

# POST https://dev-compute.sandbox.googleapis.com/compute/beta/projects/broad-epi/global/backendServices
# {
#   "backends": [
#     {
#       "balancingMode": "UTILIZATION",
#       "group": "projects/broad-epi/regions/us-east1/networkEndpointGroups/lims-cromwell-launcher-lb-endpoint-group"
#     }
#   ],
#   "connectionDraining": {
#     "drainingTimeoutSec": 0
#   },
#   "description": "",
#   "enableCDN": false,
#   "loadBalancingScheme": "EXTERNAL_MANAGED",
#   "localityLbPolicy": "ROUND_ROBIN",
#   "logConfig": {
#     "enable": true,
#     "sampleRate": 1
#   },
#   "name": "lims-cromwell-launcher-lb-backend",
#   "protocol": "HTTPS",
#   "securityPolicy": "projects/broad-epi/global/securityPolicies/default-security-policy-backend-service-lims-cromwell-launcher",
#   "sessionAffinity": "NONE",
#   "timeoutSec": 30
# }

# POST https://compute.googleapis.com/compute/v1/projects/broad-epi/global/backendServices/lims-cromwell-launcher-lb-backend/setSecurityPolicy
# {
#   "securityPolicy": "projects/broad-epi/global/securityPolicies/default-security-policy-backend-service-lims-cromwell-launcher"
# }

# POST https://compute.googleapis.com/compute/v1/projects/broad-epi/global/urlMaps
# {
#   "defaultService": "projects/broad-epi/global/backendServices/lims-cromwell-launcher-lb-backend",
#   "name": "lims-cromwell-launcher-lb"
# }

# POST https://compute.googleapis.com/compute/v1/projects/broad-epi/global/targetHttpsProxies
# {
#   "name": "lims-cromwell-launcher-lb-target-proxy",
#   "quicOverride": "NONE",
#   "sslCertificates": [
#     "projects/broad-epi/global/sslCertificates/lims-cert"
#   ],
#   "urlMap": "projects/broad-epi/global/urlMaps/lims-cromwell-launcher-lb"
# }

# POST https://compute.googleapis.com/compute/v1/projects/broad-epi/global/forwardingRules
# {
#   "IPAddress": "projects/broad-epi/global/addresses/lims-cromwell-ip",
#   "IPProtocol": "TCP",
#   "loadBalancingScheme": "EXTERNAL_MANAGED",
#   "name": "lims-cromwell-launcher-lb-forwarding-rule",
#   "networkTier": "PREMIUM",
#   "portRange": "443",
#   "target": "projects/broad-epi/global/targetHttpsProxies/lims-cromwell-launcher-lb-target-proxy"
# }

#### on-workflow-done

# Deploy VPC, Serverless VPC connector, and NAT gateway. These allow
# on-workflow-done GCF to communicate with AWS via a static IP address
# that is whitelisted in the AWS ALB security group
gcloud compute networks create lims-vpc \
    --subnet-mode=custom \
    --bgp-routing-mode=regional

gcloud compute networks vpc-access connectors create lims-vpc-connector \
    --network lims-vpc \
    --region $REGION \
    --range 10.8.0.0/28

gcloud projects add-iam-policy-binding $PROJECT \
  --member=serviceAccount:service-$PROJECT_NUMBER@gcf-admin-robot.iam.gserviceaccount.com \
  --role=roles/viewer

gcloud projects add-iam-policy-binding $PROJECT \
  --member=serviceAccount:service-$PROJECT_NUMBER@gcf-admin-robot.iam.gserviceaccount.com \
  --role=roles/compute.networkUser

gcloud compute addresses create lims-static-ip --region=$REGION

gcloud compute routers create lims-router \
    --network lims-vpc \
    --region $REGION

gcloud compute routers nats create lims-nat-config \
    --router=my-router \
    --nat-external-ip-pool=lims-static-ip \
    --nat-all-subnet-ip-ranges \
    --router-region=$REGION \
    --enable-logging

# on-workflow-done function
# --vpc-connector lims-vpc-connector \
# --egress-settings all \

