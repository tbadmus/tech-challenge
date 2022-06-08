
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
