gcloud compute instances list --flatten networkInterfaces[].accessConfigs[] --format 'csv[no-heading](name,networkInterfaces.accessConfigs.natIP)' > name_ips.txt
gcloud compute instances list --flatten networkInterfaces[].accessConfigs[] --format 'csv[no-heading](networkInterfaces.accessConfigs.natIP)' > ips.txt

