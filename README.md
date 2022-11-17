- create cloudbuild trigger: Cloud Build > Triggers > Create trigger ($main^ for dev, $release^ for prod)
- chmod 755 deploy-functions.sh to allow cloudbuild to execute
- need lims-cromwell-user SA 
- need terra / google groups [link to deploy-backend.sh where these are programmatically created]
- need cloudbuild SA -- different from default cloudbuild SA
- default cloudbuild SA needs Service Account Token Creator, Service Account Key Admin roles
- cloudbuild-kms-keyring, used for encrypting / decrypting the cromwell SA credentials

- these steps should all be managed by terraform so the entire environment can be redeployed 

RENAME REPO TO epi-lims-pipelimes