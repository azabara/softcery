terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.17.0"
    }
  }

  backend "s3" {
    bucket         	   = "bucket-of-tulips"
    key                = "state/terraform.tfstate"
    region         	   = "eu-central-1"
    encrypt        	   = true
    dynamodb_table     = "tf_lock_id"
  }
} 

# Create VPC
resource "aws_vpc" "softcery_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "softcery"
  }
}

# Create subnet
resource "aws_subnet" "softcery_subnet" {
  vpc_id     = aws_vpc.softcery_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "eu-central-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "softcery"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "softcery_igw" {
  vpc_id = aws_vpc.softcery_vpc.id
  tags = {
    Name = "softcery"
  }
}

resource "aws_eip" "main" {
  depends_on = [aws_internet_gateway.softcery_igw]
  tags = {
    Name = "softcery"
  }
}

# Create route table
resource "aws_route_table" "softcery_route_table" {
  vpc_id = aws_vpc.softcery_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.softcery_igw.id
  }
  tags = {
    Name = "softcery"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.softcery_subnet.id
  route_table_id = aws_route_table.softcery_route_table.id
}

# Create security group
resource "aws_security_group" "softcery_security_group" {
  name        = "softcery-security-group"
  description = "Allow inbound traffic on port 8080"
  tags = {
    Name = "softcery"
  }

  vpc_id = aws_vpc.softcery_vpc.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create ECR Repo
resource "aws_ecr_repository" "softcery_repository" {
  name = "softcery-repository"
}


# Create ECR Cluster
resource "aws_ecs_cluster" "softcery_cluster" {
  name = "softcery-cluster"
}

# Create IAM Role
data "aws_iam_policy_document" "ecs_spot_doc" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["spotfleet.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_spot_role" {
  name_prefix        = "softcery-ecs-spot-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_spot_doc.json
}

resource "aws_iam_role_policy_attachment" "ecs_spot_role_policy" {
  role       = aws_iam_role.ecs_spot_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole"
}

# Create Launch Template
resource "aws_launch_template" "softcery-lt" {
  name          = "softcery-lt"
  image_id      = "ami-0f673487d7e5f89ca"
  instance_type = "t2.micro"
  network_interfaces {
    subnet_id     =   aws_subnet.softcery_subnet.id
    security_groups = [aws_security_group.softcery_security_group.id]
  }
}

# Create Spot Fleet Req
resource "aws_spot_fleet_request" "ecs_spot_fleet_request" {
  iam_fleet_role      = aws_iam_role.ecs_spot_role.arn
  spot_price          = "0.01"  
  target_capacity     = 1
  allocation_strategy = "lowestPrice"

  launch_template_config {
    launch_template_specification {
      id      = aws_launch_template.softcery-lt.id
      version = aws_launch_template.softcery-lt.latest_version
    }
  }
}

# Create ASG
resource "aws_autoscaling_group" "ecs" {
  name_prefix               = "softcery-ecs-asg"
  vpc_zone_identifier       = [aws_subnet.softcery_subnet.id]
  min_size                  = 1
  max_size                  = 2
  health_check_grace_period = 0
  health_check_type         = "EC2"
  protect_from_scale_in     = false

  launch_template {
    id      = aws_launch_template.softcery-lt.id
    version = aws_launch_template.softcery-lt.latest_version
  }

  tag {
    key                 = "Name"
    value               = "softcery-ecs-cluster"
    propagate_at_launch = true
  }
}

# Create Capacity Provider
resource "aws_ecs_capacity_provider" "ecs_spot_capacity_provider" {
  name                    = "spot-capacity-provider"
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs.arn
    managed_scaling {
      status = "ENABLED"
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "ecs_spot_cluster_provider" {
  cluster_name         = aws_ecs_cluster.softcery_cluster.id
  capacity_providers   = [aws_ecs_capacity_provider.ecs_spot_capacity_provider.name]
}

# Create ECR Task
resource "aws_ecs_task_definition" "softcery_task_definition" {
  family                   = "softcery-task"
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.softcery_task_execution_role.arn

  container_definitions = jsonencode([
    {
      "name": "server",
      "image": "${aws_ecr_repository.softcery_repository.repository_url}:latest",
      "cpu": 256,
      "memory": 512,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "hostPort": 8080
        }
      ],
      "logConfiguration" = {
      "logDriver" = "awslogs",
      "options" = {
        "awslogs-region"        = "eu-central-1",
        "awslogs-group"         = aws_cloudwatch_log_group.softcery.name,
        "awslogs-stream-prefix" = "server"
      }
    },
  }])
}

# Create Task Execution Role
resource "aws_iam_role" "softcery_task_execution_role" {
  name               = "softcery-task-execution-role"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ecs-tasks.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
})
}

# Create ECR Service
resource "aws_ecs_service" "softcery_service" {
  name            = "softcery-service"
  cluster         = aws_ecs_cluster.softcery_cluster.id
  task_definition = aws_ecs_task_definition.softcery_task_definition.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  deployment_minimum_healthy_percent = "100"

  network_configuration {
    assign_public_ip = true
    subnets          = [aws_subnet.softcery_subnet.id]
    security_groups  = [aws_security_group.softcery_security_group.id]
  }
}

# Create CloudWatch Logs

resource "aws_cloudwatch_log_group" "softcery" {
  name              = "/ecs/softcery"
  retention_in_days = 14
}
