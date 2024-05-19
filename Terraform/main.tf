# Get Ubuntu AMI in Region
data "aws_ami" "ubuntu" {

  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

# Create Launch Template
resource "aws_launch_template" "ec2_website" {
  name_prefix   = "ec2-website-launch-template"
  image_id        = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [aws_security_group.ec2_website.id]
  }

  user_data = base64encode(<<-EOF
            #!/bin/bash
            sudo apt-get remove docker docker-engine docker.io
            sudo apt-get update -qq
            sudo apt-get install -y \
                apt-transport-https \
                ca-certificates \
                curl \
                software-properties-common
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

            sudo add-apt-repository \
            "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
            $(lsb_release -cs) \
            stable"

            sudo apt-get update
            sudo apt-get install docker-ce -y
            docker run -d -p 80:80 --name website olumayor99/doyenify-devops:latest
            
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ec2-website"
    }
  }
}


# Create Autoscaling Group

resource "aws_autoscaling_group" "ec2_website" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
  launch_template {
    id      = aws_launch_template.ec2_website.id
    version = "$Latest"
  }

  tag {
    key                 = "Environment"
    value               = "Dev"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}


# Create VPC
resource "aws_vpc" "ec2_website" {
  cidr_block = "10.0.0.0/16"
}

# Create Subnets
resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.ec2_website.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "subnet2" {
  vpc_id            = aws_vpc.ec2_website.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

# Create Security Group
resource "aws_security_group" "ec2_website" {
  vpc_id = aws_vpc.ec2_website.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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

# Create Load Balancer
resource "aws_lb" "ec2_website" {
  name               = "app-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ec2_website.id]
  subnets            = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]

  enable_deletion_protection = false
}

resource "aws_lb_target_group" "ec2_website" {
  name     = "app-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.ec2_website.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-299"
  }
}

resource "aws_lb_listener" "ec2_website" {
  load_balancer_arn = aws_lb.ec2_website.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2_website.arn
  }
}

resource "aws_autoscaling_attachment" "ec2_website" {
  autoscaling_group_name = aws_autoscaling_group.ec2_website.id
  lb_target_group_arn    = aws_lb_target_group.ec2_website.arn
}

# Create Internet Gateway
resource "aws_internet_gateway" "ec2_website" {
  vpc_id = aws_vpc.ec2_website.id
}

resource "aws_route_table" "ec2_website" {
  vpc_id = aws_vpc.ec2_website.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ec2_website.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.ec2_website.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.ec2_website.id
}

