# -----------------------------------------------------------------------------
# FONTES DE DADOS (Data Sources)
# -----------------------------------------------------------------------------

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# REDE (VPC, Subnets, Gateways, Route Tables)
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.tags, {
    Name = "wordpress-vpc-${var.env}"
  })
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = merge(local.tags, {
    Name = "wordpress-public-a-${var.env}"
  })
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = merge(local.tags, {
    Name = "wordpress-public-b-${var.env}"
  })
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = merge(local.tags, {
    Name = "wordpress-private-a-${var.env}"
  })
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = merge(local.tags, {
    Name = "wordpress-private-b-${var.env}"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = merge(local.tags, {
    Name = "wordpress-igw-${var.env}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(local.tags, {
    Name = "wordpress-public-rt-${var.env}"
  })
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags = merge(local.tags, {
    Name = "wordpress-nat-eip-${var.env}"
  })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  tags = merge(local.tags, {
    Name = "wordpress-nat-gw-${var.env}"
  })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = merge(local.tags, {
    Name = "wordpress-private-rt-${var.env}"
  })
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}


# -----------------------------------------------------------------------------
# GRUPOS DE SEGURANÇA (Security Groups)
# -----------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name   = "wordpress-alb-sg-${var.env}"
  vpc_id = aws_vpc.main.id
  tags   = local.tags
  ingress {
    from_port   = 80
    to_port     = 80
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

resource "aws_security_group" "ec2" {
  name   = "wordpress-ec2-sg-${var.env}"
  vpc_id = aws_vpc.main.id
  tags   = local.tags
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name   = "wordpress-rds-sg-${var.env}"
  vpc_id = aws_vpc.main.id
  tags   = local.tags
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }
}

resource "aws_security_group" "efs" {
  name   = "wordpress-efs-sg-${var.env}"
  vpc_id = aws_vpc.main.id
  tags   = local.tags
  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }
}


# -----------------------------------------------------------------------------
# EFS (Elastic File System)
# -----------------------------------------------------------------------------

resource "aws_efs_file_system" "main" {
  creation_token = "wordpress-efs-${var.env}"
  tags = merge(local.tags, {
    Name = "wordpress-efs-${var.env}"
  })
}

resource "aws_efs_mount_target" "a" {
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.private_a.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "b" {
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.private_b.id
  security_groups = [aws_security_group.efs.id]
}


# -----------------------------------------------------------------------------
# RDS (Relational Database Service)
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = "wordpress-rds-subnet-group-${var.env}"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  tags       = local.tags
}

resource "aws_db_instance" "main" {
  identifier             = "wordpress-db-${var.env}"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  username               = var.db_user
  password               = var.db_password
  db_name                = var.db_name
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  multi_az               = false # Conforme solicitado
  tags                   = local.tags
}


# -----------------------------------------------------------------------------
# IAM (Identity and Access Management)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ec2_role" {
  name = "ec2-ssm-role-${var.env}"
  tags = local.tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-ssm-instance-profile-${var.env}"
  role = aws_iam_role.ec2_role.name
  tags = local.tags
}


# -----------------------------------------------------------------------------
# EC2 (Auto Scaling, Launch Template)
# -----------------------------------------------------------------------------

resource "aws_launch_template" "main" {
  name          = "wordpress-launch-template-${var.env}"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }
  vpc_security_group_ids = [aws_security_group.ec2.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install docker -y
    service docker start
    usermod -a -G docker ec2-user
    chkconfig docker on
    yum install -y amazon-efs-utils
    EFS_ID="${aws_efs_file_system.main.id}"
    EFS_DIR="/mnt/efs"
    mkdir -p $EFS_DIR
    mount -t efs $EFS_ID:/ $EFS_DIR
    echo "$EFS_ID:/ $EFS_DIR efs _netdev,tls 0 0" >> /etc/fstab
    chown ec2-user:ec2-user $EFS_DIR
    WP_CONTENT_DIR="$EFS_DIR/wp-content"
    mkdir -p $WP_CONTENT_DIR
    chown -R ec2-user:ec2-user $WP_CONTENT_DIR
    docker run -d --name wordpress \
      -p 80:80 \
      -e WORDPRESS_DB_HOST=${aws_db_instance.main.address} \
      -e WORDPRESS_DB_USER=${var.db_user} \
      -e WORDPRESS_DB_PASSWORD=${var.db_password} \
      -e WORDPRESS_DB_NAME=${var.db_name} \
      -v $WP_CONTENT_DIR:/var/www/html/wp-content \
      --restart always \
      wordpress:latest
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = local.tags
  }
  tag_specifications {
    resource_type = "volume"
    tags          = local.tags
  }
}

resource "aws_autoscaling_group" "main" {
  name                = "wordpress-asg-${var.env}"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  health_check_type   = "ELB"
  vpc_zone_identifier = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  target_group_arns   = [aws_lb_target_group.main.arn]

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_policy" "cpu_scaling" {
  name                   = "wordpress-cpu-scaling-policy-${var.env}"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}


# -----------------------------------------------------------------------------
# LOAD BALANCER (ALB)
# -----------------------------------------------------------------------------

resource "aws_lb" "main" {
  name               = "wordpress-alb-${var.env}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  tags               = local.tags
}

resource "aws_lb_target_group" "main" {
  name     = "wordpress-tg-${var.env}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  tags     = local.tags

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  stickiness {
    cookie_duration = 86400 # Mantém a sessão por 1 dia
    enabled         = true  # Altere esta linha para true
    type            = "lb_cookie"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  tags              = local.tags

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}