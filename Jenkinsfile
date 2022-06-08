
/* ENVIRONMENT BRANCHES used to Deploy*/
environment_branches = ['dev', 'master']

pipeline {
    agent {any}

    stages {
        stage('Test') {

            steps {
                sh "echo test step"
                }
        }
        
        stage('Build image') {

            steps {
                sh '''
                    packer validate ami/ami.json
                    packer build ami/ami.json
                '''
                }
        }
        
        // stage('Deploy to Environment') {
        //     when {
        //         expression {
        //             return env.BRANCH_NAME in environment_branches;
        //             // Run only for stable branches and not PRs
        //         }
        //     }

        //     steps {
        //         script {
        //             // SET params for dev
        //             withAWS(role: "saic-tech-ECSRole-us-west-2", roleAccount: "020793260732", roleSessionName: "Jenkins") {
        //                 sh script:'''
        //                     cd 
        //                 ''', label: "Deploy API"
        //                 for (GROUP in env.GROUPS) {
        //                     env.ALERT_STREAM_ARN = sh(
        //                         returnStdout: true, 
        //                         script: "aws dynamodbstreams list-streams --table-name ${GROUP}_Alert --region ap-southeast-2 --query Streams[*].StreamArn  --output text"
        //                     ).trim()
        //                     sh "aws lambda create-event-source-mapping --function-name itrazo-${env.APP_ENV}-SendAlert --batch-size 500 --starting-position LATEST --event-source-arn ${env.ALERT_STREAM_ARN} --region ap-southeast-2 "
        //                     env.SCAN_STREAM_ARN = sh(
        //                         returnStdout: true, 
        //                         script: "aws dynamodbstreams list-streams --table-name ${GROUP}_ScanRecord  --region ap-southeast-2 --query Streams[*].StreamArn  --output text"
        //                     ).trim()
        //                     sh "aws lambda create-event-source-mapping --function-name itrazo-${env.APP_ENV}-SendScan --batch-size 500 --starting-position LATEST --event-source-arn ${env.SCAN_STREAM_ARN} --region ap-southeast-2 "
        //                 }
        //             }
        //         }
        //     }
        // }
    }
}
