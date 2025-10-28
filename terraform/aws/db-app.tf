# NOTE: This code assumes you have a VPC, subnets, and variables defined elsewhere.
# Example required variables:
# variable "db_name" {}
# variable "resource_prefix" {}

# locals {
#   resource_prefix = {
#     value = var.resource_prefix
#   }
# }

### 1. Store the DB Password Securely in AWS Secrets Manager
resource "random_password" "db" {
  length  = 16
  special = true
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.resource_prefix}-rds-credentials"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id     = aws_secretsmanager_secret.db_credentials.id
  secret_string = random_password.db.result
}

### 2. AWS RDS Database Instance
resource "aws_db_instance" "default" {
  # FIX: The argument for the initial database is 'db_name', not 'name'.
  db_name                = var.db_name
  identifier             = "rds-${local.resource_prefix.value}"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = "admin"
  # FIX: Password is now taken from the random_password resource.
  password               = random_password.db.result
  option_group_name      = aws_db_option_group.default.name
  parameter_group_name   = aws_db_parameter_group.default.name
  db_subnet_group_name   = aws_db_subnet_group.default.name
  # FIX: Removed deprecated interpolation syntax.
  vpc_security_group_ids = [aws_security_group.default.id]

  apply_immediately       = true
  multi_az                = false
  backup_retention_period = 0
  storage_encrypted       = false
  skip_final_snapshot     = true
  monitoring_interval     = 0
  publicly_accessible     = true

  tags = merge({
    Name        = "${local.resource_prefix.value}-rds"
    Environment = local.resource_prefix.value
    }, {
    git_repo = "terragoat" # NOTE: Simplified tags for clarity
  })

  # NOTE: Lifecycle block is good practice for managing passwords.
  lifecycle {
    ignore_changes = [password]
  }
}

### 3. Database Supporting Resources (Option, Parameter, Subnet Groups)
resource "aws_db_option_group" "default" {
  name                     = "og-${local.resource_prefix.value}"
  engine_name              = "mysql"
  major_engine_version     = "8.0"
  option_group_description = "Terraform OG"
  tags = {
    Name = "${local.resource_prefix.value}-og"
  }
}

resource "aws_db_parameter_group" "default" {
  name        = "pg-${local.resource_prefix.value}"
  family      = "mysql8.0"
  description = "Terraform PG"

  parameter {
    name  = "character_set_client"
    value = "utf8"
  }

  parameter {
    name  = "character_set_server"
    value = "utf8"
  }
  tags = {
    Name = "${local.resource_prefix.value}-pg"
  }
}

resource "aws_db_subnet_group" "default" {
  name = "sg-${local.resource_prefix.value}"
  # FIX: Removed deprecated interpolation. Assumes subnets exist.
  subnet_ids  = [aws_subnet.web_subnet.id, aws_subnet.web_subnet2.id]
  description = "Terraform DB Subnet Group"
  tags = {
    Name = "sg-${local.resource_prefix.value}"
  }
}

### 4. Security Groups and Rules
resource "aws_security_group" "default" {
  name   = "${local.resource_prefix.value}-rds-sg"
  vpc_id = aws_vpc.web_vpc.id
  tags = {
    Name = "${local.resource_prefix.value}-rds-sg"
  }
}

resource "aws_security_group_rule" "ingress" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  # FIX: Removed deprecated interpolation.
  cidr_blocks       = [aws_vpc.web_vpc.cidr_block]
  security_group_id = aws_security_group.default.id
}

resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.default.id # FIX: Removed deprecated interpolation.
}


### 5. EC2 Instance IAM Role and Policy
resource "aws_iam_role" "ec2role" {
  name = "${local.resource_prefix.value}-role"
  path = "/"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
  tags = {
    Name = "${local.resource_prefix.value}-role"
  }
}

# FIX: This policy now includes permission to read the specific secret.
resource "aws_iam_policy" "ec2policy" {
  name = "${local.resource_prefix.value}-policy"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action   = [
          "s3:*",
          "ec2:*",
          "rds:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      # NOTE: Added permission to fetch the database password from Secrets Manager.
      {
        Action   = "secretsmanager:GetSecretValue"
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_policy_attach" {
  role       = aws_iam_role.ec2role.name
  policy_arn = aws_iam_policy.ec2policy.arn
}

resource "aws_iam_instance_profile" "ec2profile" {
  name = "${local.resource_prefix.value}-profile"
  role = aws_iam_role.ec2role.name
}

### 6. EC2 Instance with Secure User Data
data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "db_app" {
  ami                    = data.aws_ami.amazon-linux-2.id
  instance_type          = "t2.nano"
  iam_instance_profile   = aws_iam_instance_profile.ec2profile.name
  vpc_security_group_ids = [aws_security_group.web-node.id] # Assumes this SG exists
  subnet_id              = aws_subnet.web_subnet.id      # Assumes this subnet exists

  # FIX: User data now fetches the password securely from Secrets Manager.
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd php php-mysqlnd jq
    
    # Get the instance's region
    EC2_REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
    
    # Fetch the secret from Secrets Manager
    SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.db_credentials.id} --region $EC2_REGION --query SecretString --output text)
    
    # Extract the password from the JSON secret
    DB_PASSWORD=$(echo $SECRET_JSON | jq -r '.')

    systemctl enable httpd
    systemctl start httpd
    
    mkdir -p /var/www/inc
    
    # Create the config file securely
    cat << EnD > /var/www/inc/dbinfo.inc
<?php
define('DB_SERVER', '${aws_db_instance.default.endpoint}');
define('DB_USERNAME', '${aws_db_instance.default.username}');
define('DB_PASSWORD', "\$DB_PASSWORD");
define('DB_DATABASE', '${aws_db_instance.default.db_name}'); # FIX: Correct attribute is 'db_name'
?>
EnD

    chown root:root /var/www/inc/dbinfo.inc
    chmod 600 /var/www/inc/dbinfo.inc

    # The rest of your index.php setup follows...
    # (PHP code omitted for brevity but should be included here)
    cp /tmp/index.php /var/www/html/index.php # Assuming you create index.php
    
    EOF

  tags = {
    Name = "${local.resource_prefix.value}-dbapp"
  }
}

### 7. Outputs
output "db_app_public_dns" {
  description = "DB App Public DNS name"
  value       = aws_instance.db_app.public_dns
}

output "db_endpoint" {
  description = "DB Endpoint"
  value       = aws_db_instance.default.endpoint
}