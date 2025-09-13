# --- Provider and Terraform Configuration ---
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source = "hashicorp/tls"
    }
    local = {
      source = "hashicorp/local"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- AUTOMATED SSH KEY GENERATION ---
# This block generates a new, secure RSA key pair locally in memory.
resource "tls_private_key" "jenkins_pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# This block takes the public part of the generated key and uploads it to AWS.
resource "aws_key_pair" "jenkins_key" {
  key_name   = "jenkins" # The name it will have in AWS
  public_key = tls_private_key.jenkins_pk.public_key_openssh
}

# This block saves the private part of the generated key to a file named 'jenkins-key.pem'.
# You will use this file to SSH into the server.
resource "local_file" "jenkins_private_key" {
  content         = tls_private_key.jenkins_pk.private_key_pem
  filename        = "jenkins-key.pem"
  file_permission = "0400" # Sets read-only permissions for the user
}

# --- NETWORKING (No changes) ---
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags       = { Name = "devops-task-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags                    = { Name = "devops-task-public-subnet" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "devops-task-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "devops-task-public-rt" }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "jenkins_sg" {
  name   = "jenkins-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app_sg" {
  name   = "app-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- IAM ROLE FOR JENKINS (No changes) ---
resource "aws_iam_role" "jenkins_role" {
  name               = "jenkins-ec2-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_policy_attach" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "jenkins-instance-profile"
  role = aws_iam_role.jenkins_role.name
}

# --- JENKINS EC2 INSTANCE (CORRECTED) ---
resource "aws_instance" "jenkins_server" {
  ami           = "ami-0c7217cdde317cfec" # Ubuntu 22.04 LTS (Latest as of Sep 2025)
  instance_type = "t2.medium"
  key_name      = aws_key_pair.jenkins_key.key_name
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins_profile.name

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              # Install Java 17, which is required by modern Jenkins versions
              sudo apt-get install -y openjdk-17-jre
              
              # Install Jenkins
              curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
                /usr/share/keyrings/jenkins-keyring.asc > /dev/null
              echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
                https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
                /etc/apt/sources.list.d/jenkins.list > /dev/null
              sudo apt-get update -y
              sudo apt-get install -y jenkins
              sudo systemctl start jenkins
              sudo systemctl enable jenkins
              
              # Install Docker
              sudo apt-get install -y docker.io
              sudo usermod -aG docker jenkins
              sudo usermod -aG docker ubuntu
              sudo systemctl restart docker
              
              # Install AWS CLI
              sudo apt-get install -y unzip
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              sudo ./aws/install
              EOF
  tags = { Name = "Jenkins Server" }
}

# --- ECR REPOSITORY (No changes) ---
resource "aws_ecr_repository" "app_repo" {
  name = "devops-task-app"
}

# --- ECS FARGATE CLUSTER (No changes) ---
resource "aws_ecs_cluster" "main" {
  name = "devops-task-cluster"
}

resource "aws_ecs_task_definition" "app_task" {
  family                   = "devops-task-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = jsonencode([
    {
      name      = "devops-task-container",
      image     = "${aws_ecr_repository.app_repo.repository_url}:latest",
      essential = true,
      portMappings = [
        {
          containerPort = 3000,
          hostPort      = 3000
        }
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name,
          "awslogs-region"        = "us-east-1",
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "main" {
  name            = "devops-task-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.public.id]
    security_groups = [aws_security_group.app_sg.id]
    assign_public_ip = true
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs_task_execution_role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- CloudWatch (No changes) ---
resource "aws_cloudwatch_log_group" "app_logs" {
  name = "/ecs/devops-task-app"
}

# --- Outputs (No changes) ---
output "jenkins_public_ip" {
  value = aws_instance.jenkins_server.public_ip
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app_repo.repository_url
}

output "ecs_service_name" {
  value = aws_ecs_service.main.name
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}