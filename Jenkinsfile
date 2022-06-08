/* ENVIRONMENT BRANCHES used to Deploy*/
environment_branches = ['dev', 'master']

pipeline {
    agent any

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
        stage('Create keypair') {

            steps {
                withCredentials([file(credentialsId: 'techkey', variable: 'techkeypub')]) {
                    sh '''
                        echo $techkeypub>keypairpub
                        cat $PWD/keypairpub
                        aws ec2 import-key-pair --region us-west-2 --key-name mvp --public-key-material file://$PWD/keypairpub
                    '''
                }
                }
        }
        
        stage('Deploy to Environment') {
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
                            terraform init --reconfigure
                            terraform plan
                        '''
                }
            }
        }
    }
}
