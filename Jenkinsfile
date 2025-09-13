pipeline {
    agent any

    environment {
        AWS_REGION         = "us-east-1"
    
        ECR_REPOSITORY_URL = "841961777599.dkr.ecr.us-east-1.amazonaws.com/devops-task-app"
        ECS_CLUSTER_NAME   = "devops-task-cluster"
        ECS_SERVICE_NAME   = "devops-task-service"
    }

    stages {
        stage('Checkout') {
            steps {
                script {
                    cleanWs()
                    checkout scm
                }
            }
        }

        stage('Build') {
            steps {
                script {
                    echo "--- Building the application ---"
                    sh 'npm install'
                }
            }
        }

        stage('Dockerize and Push') {
            steps {
                script {
                    echo "--- Building Docker image ---"
                    // The ECR_REPOSITORY_URL is now taken directly from the environment block
                    def dockerImage = docker.build("${env.ECR_REPOSITORY_URL}:${env.BUILD_NUMBER}", ".")
                    
                    echo "--- Pushing image to ECR ---"
                    sh "aws ecr get-login-password --region ${env.AWS_REGION} | docker login --username AWS --password-stdin ${env.ECR_REPOSITORY_URL}"
                    dockerImage.push()
                }
            }
        }

        stage('Deploy to ECS') {
            steps {
                script {
                    echo "--- Deploying to ECS Fargate ---"
                    // Update the ECS service to use the new Docker image, forcing a new deployment
                    sh """
                    aws ecs update-service --cluster ${env.ECS_CLUSTER_NAME} --service ${env.ECS_SERVICE_NAME} --force-new-deployment
                    """
                }
            }
        }
    }

    post {
        always {
            echo "Pipeline finished."
        }
    }
}

