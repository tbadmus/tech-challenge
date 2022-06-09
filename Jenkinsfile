/* ENVIRONMENT BRANCHES used to Deploy*/
environment_branches = ['dev', 'master']

pipeline {
    agent any
    
    environment {
        AWS_DEFAULT_REGION = "us-west-2"
    }
    
    stages {
//         stage('Sonarqube') {
//             steps {
//                 script{
//                     def scannerHome = tool 'Sonar';
//                 }
//                 withSonarQubeEnv('SonarQube') {
//                     sh "${scannerHome}/bin/sonar-scanner"
//                 }
//                 timeout(time: 10, unit: 'MINUTES') {
//                     waitForQualityGate abortPipeline: true
//                 }
//             }
//         }
        stage('Vulnurabilities and security scanning') {

            steps {
                sh '''
                    trivy fs -security-checks vuln,config app/
                    docker build -t node -f app/Dockerfile app
                    trivy image node
                '''
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
        stage('Create keypair') {

            steps {
                withCredentials([string(credentialsId: 'pubkey', variable: 'SECRET')]) {
                    sh '''
                        echo ${SECRET}>/tmp/keypairpub
                        aws ec2 import-key-pair --key-name mvp --public-key-material fileb:///tmp/keypairpub || true
                    '''
                }
                }
        }
        
        stage('Deploy infrastructure') {
            when {
                expression {
                    return env.BRANCH_NAME in environment_branches;
                }
            }

            steps {
                script {
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
