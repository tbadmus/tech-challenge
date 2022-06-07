echo "Creating new AMI using packer....."
packer build ami/ami.json
echo "Generating keypair in home directory to be used by bastion host"
ssh-keygen -q -b 2048 -f techkey -P "" -t rsa -N '' <<< $'\ny' >/dev/null 2>&1
aws ec2 import-key-pair --key-name "mvp" --public-key-material fileb://$PWD/techkey.pub
echo "Formatting Terraform changes...."
terraform init --reconfigure 
terraform fmt --recursive
echo "Provisioning infrastructure using Terraform......"
terraform apply -auto-approve