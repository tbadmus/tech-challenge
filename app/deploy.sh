sudo docker build -t node .
sudo docker tag node $REPO_URL
REPO=$(echo $REPO_URL|awk -F/ '{print $1}')
aws ecr get-login-password |sudo docker login --username AWS --password-stdin $REPO
sudo docker push $REPO_URL
sed -i -e "s%REPO_URL%${REPO_URL}%g" deployment.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml