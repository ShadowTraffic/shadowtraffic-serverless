variable "aws_region" {
  default = "us-east-2"
}

provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "ShadowTraffic VPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "ShadowTraffic IGW"
  }
}

resource "aws_subnet" "subnet" {
  vpc_id = aws_vpc.vpc.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "ShadowTraffic Subnet"
  }
}

resource "aws_security_group" "security_group" {
  vpc_id = aws_subnet.subnet.vpc_id
  name = "ShadowTraffic Security Group"

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ShadowTraffic Security Group"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id = aws_subnet.subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_ecs_cluster" "ecs" {
  name = "ShadowTrafficCluster"
}

resource "aws_ecs_cluster_capacity_providers" "ecs_providers" {
  cluster_name = aws_ecs_cluster.ecs.name
  capacity_providers = ["FARGATE"]
}

variable "LICENSE_ID" {
  type = string
}

variable "LICENSE_EDITION" {
  type = string
}

variable "LICENSE_EMAIL" {
  type = string
}

variable "LICENSE_EXPIRATION" {
  type = string
}

variable "LICENSE_ORGANIZATION" {
  type = string
}

variable "LICENSE_SIGNATURE" {
  type = string
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com",
      },
    }],
  })
}

resource "aws_iam_role_policy" "ecs_execution_role_policy" {
  name = "ecs_execution_role_policy"
  role = aws_iam_role.ecs_execution_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
        Effect   = "Allow",
        Resource = "*",
      },
    ],
  })
}

resource "aws_ecs_task_definition" "definition" {
  family = "ShadowTrafficRunner"
  cpu = 256
  memory = 512
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name = "shadowtraffic"
      image = "shadowtraffic/shadowtraffic:latest"

      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-create-group" = "true"
          "awslogs-group" = "shadowtraffic-logs"
          "awslogs-region" = var.aws_region
          "awslogs-stream-prefix" = "ShadowTraffic"
        }
      }
      
      environment = [
        {
          name = "LICENSE_ID",
          value = var.LICENSE_ID
        },
        {
          name = "LICENSE_EDITION",
          value = var.LICENSE_EDITION
        },
        {
          name = "LICENSE_EMAIL",
          value = var.LICENSE_EMAIL,
        },
        {
          name = "LICENSE_EXPIRATION",
          value = var.LICENSE_EXPIRATION,
        },
        {
          name = "LICENSE_ORGANIZATION",
          value = var.LICENSE_ORGANIZATION,
        },
        {
          name = "LICENSE_SIGNATURE",
          value = var.LICENSE_SIGNATURE
        }
      ]
    }
  ])
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com",
        },
      },
    ],
  })
}

resource "aws_iam_role_policy_attachment" "ecs_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
  role = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  role = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution_role_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role = aws_iam_role.lambda_role.name
}

data "archive_file" "lambda_source" {
  type = "zip"
  source_file = "lambda/lambda.py"
  output_path = "lambda.zip"
}

resource "aws_lambda_function" "shadowtraffic_lambda" {
  filename = "lambda.zip"
  function_name = "shadowtraffic_runner"
  handler = "lambda.handler"
  role = aws_iam_role.lambda_role.arn
  source_code_hash = data.archive_file.lambda_source.output_base64sha256
  runtime = "python3.12"
}

resource "aws_apigatewayv2_api" "http_api" {
  name = "ShadowTraffic HTTP API"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "integration" {
  api_id = aws_apigatewayv2_api.http_api.id
  integration_uri = aws_lambda_function.shadowtraffic_lambda.invoke_arn
  integration_method = "POST"
  integration_type = "AWS_PROXY"
}

resource "aws_apigatewayv2_route" "route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "$default"

  target = "integrations/${aws_apigatewayv2_integration.integration.id}"
}

resource "aws_apigatewayv2_stage" "stage" {
  api_id = aws_apigatewayv2_api.http_api.id
  name = "generate"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit = 100
    throttling_burst_limit = 150
    detailed_metrics_enabled = false
  }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shadowtraffic_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

output "http_api_url" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}

