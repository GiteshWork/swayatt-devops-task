DevOps Task - Write-up
This document provides a brief overview of the tools used, challenges faced, and potential improvements for this CI/CD project.

Tools & Services Used
Version Control: GitHub was used for source code management, utilizing a main/dev branching strategy.

Infrastructure as Code (IaC): Terraform was used to provision and manage the entire AWS infrastructure, including networking (VPC, Subnets), the Jenkins EC2 instance, the ECR repository, and the ECS Fargate cluster. This ensures the environment is repeatable, version-controlled, and can be torn down cleanly.

CI/CD Server: Jenkins was used as the automation server, running on a dedicated EC2 instance.

Containerization: Docker was used to package the Node.js application into a portable and lightweight image using a multi-stage Dockerfile for optimization.

Container Registry: AWS Elastic Container Registry (ECR) was used to securely store the versioned Docker images.

Deployment Environment: AWS Elastic Container Service (ECS) on Fargate was chosen as the deployment platform. This serverless approach simplifies orchestration, as AWS manages the underlying compute infrastructure.

Monitoring & Logging: AWS CloudWatch was configured via the ECS task definition to automatically collect and centralize logs from the running application container.

Challenges Faced & Solutions
Initial Jenkins Server Failures: The most significant challenge was the Jenkins EC2 instance failing to start the Jenkins service.

Problem: The initial user_data script installed an outdated version of Java (Java 11), which is not compatible with modern Jenkins releases that require Java 17+.

Solution: After debugging via SSH and inspecting the systemctl and journalctl logs, the root cause was identified. The Terraform user_data script was updated to install openjdk-17-jre, and the EC2 instance was replaced. This "fix-in-code" approach ensures the solution is permanent and automated.

Infrastructure Idempotency Issues: Several InvalidAMIID.NotFound and InvalidKeyPair.NotFound errors occurred during the Terraform provisioning process.

Problem: Hardcoding AMI IDs is a fragile practice as they are frequently retired by AWS. Manual key creation also introduced room for typos.

Solution: The Terraform code was refactored to be more robust. I implemented a data "aws_ami" block to dynamically look up the latest official Ubuntu 22.04 AMI at runtime. I also automated the SSH key generation and management directly within Terraform using the tls_private_key resource, which eliminated all manual steps and potential for error.

ECS Deployment Failures (CannotPullContainerError): The final pipeline stage initially failed because the ECS task could not find the Docker image.

Problem: The ECS task definition was configured to pull the latest tag, but the initial pipeline was only pushing a uniquely versioned tag (e.g., :7).

Solution: The Jenkinsfile was updated to be more explicit. It now builds the image, adds two tags (:latest and the unique build number), and then pushes both tags to ECR. This ensures the versioned artifact is stored while also providing the stable latest tag that the ECS service expects.

Possible Improvements
If more time were allotted, I would implement the following improvements:

Separate Terraform State Management: Use a remote backend like an S3 bucket for the Terraform state file to enable team collaboration and secure state management.

Enhanced Security:

Create a more granular IAM role for the Jenkins server instead of using AdministratorAccess, following the principle of least privilege.

Place the ECS service in a private subnet and use an Application Load Balancer (ALB) in the public subnet to securely expose the application.

Advanced CI/CD:

Implement a separate "testing" stage in the Jenkinsfile to run unit or integration tests (npm test).

Add a manual approval step in the pipeline before deploying to a production-like environment.

Webhook Automation: Configure a proper GitHub webhook in the Jenkins job to automatically trigger the pipeline on every push to the dev branch, removing the need to click "Build Now" manually.

Monitoring & Logging
This project uses native AWS services for monitoring and logging, configured automatically via Terraform. This approach is simple, robust, and requires no extra agents.

How to View Application Logs
All logs (stdout and stderr) from the running Node.js application container are automatically captured and sent to AWS CloudWatch Logs.

To view the live logs:

Navigate to CloudWatch: In the AWS Management Console, go to the CloudWatch service.

Select Log Groups: On the left-hand menu, under "Logs," click on Log groups.

Find Your Log Group: In the list, find and click on the log group named /ecs/devops-task-app. This was created by the Terraform script.

View Log Streams: Inside the log group, you will see one or more "log streams." Each stream corresponds to a running instance of your application container. Click on the most recent log stream to view its output.

See the Live Logs: You can now see all the console output from your application, including the "Server running on port 3000" message and any future request logs. This is the primary place to troubleshoot application errors.

How to View Service Metrics
Basic but essential performance metrics for the ECS service are also automatically sent to AWS CloudWatch Metrics.

To view the service metrics:

Navigate to ECS: In the AWS Management Console, go to the ECS service.

Select Your Cluster: Click on the devops-task-cluster.

Select Your Service: Click on the devops-task-service.

View Metrics: Click on the "Metrics" tab.

Analyze Performance: You will see graphs for the service's CPU Utilization and Memory Utilization. These metrics are crucial for understanding the performance and resource consumption of your application over time and are essential for setting up autoscaling or performance alarms.