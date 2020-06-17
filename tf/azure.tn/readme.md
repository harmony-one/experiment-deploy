# login to azure accont
az login

# init
terraform init

# plan
terraform plan

# deploy 20 nodes
terraform deploy -var 'vm_count=20' -auto-prove

# terminate
terraform destroy
