pipeline {
    agent any

    environment {
        AWS_REGION        = "us-east-1"
        ECR_REPOSITORY_URL = "" // This will be dynamically fetched in the pipeline
        ECS_CLUSTER_NAME  = "devops-task-cluster"
        ECS_SERVICE_NAME  = "devops-task-service"
    }

    stages {
        stage('Checkout') {
            steps {
                script {
                    // Clean the workspace and checkout the code from GitHub
                    cleanWs()
                    checkout scm
                }
            }
        }

        stage('Build') {
            steps {
                script {
                    echo "--- Building the application ---"
                    // Install dependencies. Tests would run here in a real project.
                    sh 'npm install'
                }
            }
        }

        stage('Build & Push Docker Image') {
            steps {
                script {
                    echo "--- Building & Pushing Docker image ---"
                    // Get the ECR URL dynamically from the Terraform state
                    // This command runs inside the Jenkins workspace, where the terraform folder exists
                    def terraformEcrUrl = sh(script: "cd terraform && terraform output -raw ecr_repository_url", returnStdout: true).trim()
                    env.ECR_REPOSITORY_URL = terraformEcrUrl

                    // Build the Docker image with a unique tag (the Jenkins build number)
                    def dockerImage = docker.build("${env.ECR_REPOSITORY_URL}:${env.BUILD_NUMBER}", ".")
                    
                    // Log in to AWS ECR and push the image using the EC2 instance's IAM Role
                    sh "aws ecr get-login-password --region ${env.AWS_REGION} | docker login --username AWS --password-stdin ${env.ECR_REPOSITORY_URL}"
                    dockerImage.push()
                }
            }
        }

        stage('Deploy to ECS') {
            steps {
                script {
                    echo "--- Deploying to ECS Fargate ---"
                    // Update the ECS service to use the new task definition, forcing a new deployment
                    sh """
                    aws ecs update-service --cluster ${env.ECS_CLUSTER_NAME} --service ${env.ECS_SERVICE_NAME} --force-new-deployment
                    """
                    echo "Deployment triggered successfully."
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

