variable "app_port" {
  type = number
  default = 80
}

variable "load_balancer_port" {
  type = number
  default = 80
}

variable "vpc_link_port" {
  type = number
  default = 80
}

variable "http_api_stage_name" {
  type = string
  default = "app"
}

provider "aws" {
  profile = "default"
  region = "us-east-2"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_availability_zones" "all" { }

# Security groups

resource "aws_security_group" "app_instance" {
  name = "app-instance"

  ingress {
    from_port = var.app_port
    to_port = var.app_port
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "load_balancer" {
  name = "load-balancer"

  ingress {
    from_port = var.load_balancer_port
    to_port = var.load_balancer_port
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "vpc_link" {
  name = "vpc-link"

  ingress {
    from_port = var.vpc_link_port
    to_port = var.vpc_link_port
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch configuration and autoscaling group

resource "aws_launch_configuration" "app" {
  name = "launch-configuration"

  image_id = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"

  user_data = <<-EOF
              #!/bin/bash
              mkdir ${var.http_api_stage_name}
              echo "Hello World!" > ${var.http_api_stage_name}/index.html
              nohup busybox httpd -f -p ${var.app_port} &
              EOF

  security_groups = [aws_security_group.app_instance.id]
}

resource "aws_autoscaling_group" "app" {
  name = "autoscaling-group"

  launch_configuration = aws_launch_configuration.app.id

  min_size = 2
  max_size = 10

  target_group_arns = [aws_lb_target_group.app.arn]

  availability_zones = data.aws_availability_zones.all.names

  tag {
    key = "Name"
    value = "app-instance"
    propagate_at_launch = true
  }
}

# Load balancer

resource "aws_lb" "app" {
  name = "load-balancer"

  internal = true
  load_balancer_type = "application"
  security_groups = [aws_security_group.load_balancer.id]
  subnets = data.aws_subnet_ids.default.ids
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn

  port = var.load_balancer_port
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_target_group" "app" {
  name = "load-balancer-target-group"

  port = var.app_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check {
    interval = 30
    path = "/${var.http_api_stage_name}"
    port = var.app_port
    protocol = "HTTP"
    timeout = 5
    healthy_threshold = 3
    unhealthy_threshold = 3
  }
}

# HTTP API gateway

resource "aws_apigatewayv2_vpc_link" "app" {
  name = "http-api-vpc-link"

  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids = data.aws_subnet_ids.default.ids
}

resource "aws_apigatewayv2_api" "app" {
  name = "http-api"

  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "app" {
  api_id = aws_apigatewayv2_api.app.id

  integration_type = "HTTP_PROXY"
  connection_id = aws_apigatewayv2_vpc_link.app.id
  connection_type = "VPC_LINK"
  integration_method = "GET"
  integration_uri = aws_lb_listener.app.arn
}

resource "aws_apigatewayv2_route" "app" {
  api_id = aws_apigatewayv2_api.app.id

  route_key = "$default"
  target = "integrations/${aws_apigatewayv2_integration.app.id}"
}

resource "aws_apigatewayv2_stage" "app" {
  api_id = aws_apigatewayv2_api.app.id

  name = var.http_api_stage_name

  auto_deploy = true
}

# Database

resource "aws_db_instance" "app" {
  allocated_storage = 20
  storage_type = "gp2"
  engine = "mysql"
  engine_version = "5.7"
  identifier = "database"
  instance_class = "db.t2.micro"
  name = "db"
  username = "user"
  password = "password"
  skip_final_snapshot = true
}

output "invoke_url" {
  value = aws_apigatewayv2_stage.app.invoke_url
}
