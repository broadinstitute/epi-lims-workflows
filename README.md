- create cloudbuild trigger: Cloud Build > Triggers > Create trigger ($main^ for dev, $release^ for prod)
- chmod 755 deploy-functions.sh to allow cloudbuild to execute
- there are a few different SAs required
  - lims-cromwell-user SA [Pub/Sub Publisher, SA User, Storage Admin and/or Storage Object Admin]
  - default cloudbuild (identity of cloudbuild) [needs a number of permissions, including EventArc, Service Account Token Creator, Service Account Key Admin]
  - default compute (identity of google cloud functions) [needs EventArc event receiver and Pub/Sub]
  - cloudbuild (external services)
  - GCS SA (needs Pub/Sub)
  - cromwell
  - genotyping?
- need terra / google groups [these are programmatically created in deploy-backend.sh in original repo]
- compute SA (for functions) needs Cloud KMS CryptoKey Decrypter
- cloudbuild-kms-keyring, used for encrypting / decrypting the cromwell SA credentials
- cloudcopy is separate repo and runs on epigenomics host 
  requires pub/sub topic
  server.ts subscribes to it
- lims api user manually created in lims called lims-api-user
- lims username/password manually created in GCP secret called lims-api-user
- cloud functions need to be able to hit LIMS API behind firewall, which means that FN needs to be associated with a static IP so that can add IP to ingress rules of EC2 ALB. To associate a function with a static IP, need to do the following (this was done manually)
  - https://cloud.google.com/functions/docs/networking/network-settings#route-egress-to-vpc 

- these steps should all be managed by terraform and/or cloudbuild so the entire environment can be redeployed (ex cloudbuild or terraform should take care of setting permissions -- should figure out if want to use cloudbuild only or cloudbuild/TF, TF good for things like VPC 

- run the build regularly to catch errors
- devise testing framework (with real data)