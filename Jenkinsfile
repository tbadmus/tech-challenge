/* ENVIRONMENT BRANCHES used to Deploy*/
environment_branches = ['dev', 'master']

pipeline {
    agent any
    
    environment {
        AWS_DEFAULT_REGION = "us-west-2"
    }
    
    stages {
        stage('Test') {

            steps {
                sh "echo test step"
                }
        }
        
//         stage('Build image') {

//             steps {
//                 sh '''
//                     packer validate ami/ami.json
//                     packer build ami/ami.json
//                 '''
//                 }
//         }
//         stage('Create keypair') {

//             steps {
//                 withCredentials([file(credentialsId: 'techkey', variable: 'techkeypub')]) {
//                     sh '''
//                         echo $techkeypub>keypairpub
//                         cat $PWD/keypairpub
//                         aws ec2 import-key-pair --region us-west-2 --key-name mvp --public-key-material fileb://$PWD/keypairpub
//                     '''
//                 }
//                 }
//         }
        
        stage('Deploy infrastructure') {
            when {
                expression {
                    return env.BRANCH_NAME in environment_branches;
                    // Run only for stable branches and not PRs
                }
            }

            steps {
                script {
                    // SET params for dev
                        sh '''
                            echo "Formatting Terraform changes...."
                            terraform init --reconfigure 
                            terraform fmt --recursive
                            echo "Provisioning infrastructure using Terraform......"
                            terraform apply -auto-approve
                        '''
                }
            }
        }
        stage('Deploy application in K8S') {
            steps {
                sh '''
                     terraform init --reconfigure
                     REPO_URL=$(terraform output ecr_repo_url|sed -e 's/"//g')
                     cd app && aws eks update-kubeconfig --name mvp-cluster
                     docker build -t node .
                     docker tag node $REPO_URL
                     REPO=$(echo $REPO_URL|awk -F/ '{print $1}')
                     aws ecr get-login-password |docker login --username AWS --password-stdin $REPO
                     docker push $REPO_URL
                     sed -i -e "s%REPO_URL%${REPO_URL}%g" deployment.yaml
                     kubectl apply -f deployment.yaml
                     kubectl apply -f service.yaml
                '''
                }
        }
    }
}
