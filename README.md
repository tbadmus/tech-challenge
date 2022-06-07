1. Update the region and base image in ami.json under ami folder to deploy new packer image if it is in different region.
2. Configure local AWS credentials using aws configure sso and set default profile using export AWS_PROFILE=<aws configure sso suggested profile in last step>. Make sure to set default region too.
3. Run the deployment by bash bootstrap.sh It will show you bastion's IP address to ssh once apply is completed.
4. Connect to bastion host using ssh with key generated at your local directory. If you changed the path in bootstrap path then refer the path script.
5. Repeat step 2 
6. Configure kubernetes credentials by command aws eks update-kubeconfig --name <eks_cluster_name> We are configuring in bastion because Kubernetes cluster is provisioned in vpc2 which is private and cannot be accessed from local without VPN.
7. Check if you are able to see running pods by kubectl pods -A 
8. Run the bash deploy.sh script in bastion host to build the docker image and deploy the application in kubernetes cluster
10. Once script is finished then get application endpoing by kubectl get svc and you should see load balancer endpoint
11. Run curl <load_balancer_endpoint> 

Note: 
 - If you are changing the region or AWS account then please find and replace the values in all the files.