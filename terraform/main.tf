//-------------------------------------------
// Provider
//-------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

   backend "s3" {
       key    = "terraform.tfstate"
       region = "us-east-1"
   }

}

provider "aws" {
  region  = "us-east-1"
}

//-------------------------------------------
// Frontend
//-------------------------------------------

module "main_site_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "main-site-innovatehk"
  acl    = "public-read"

  versioning = {
    enabled = true
  }

  website = {
    index_document = "index.html"
  }

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${module.main_site_bucket.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

module "reports_site_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "reports-page-innovatehk"
  acl    = "public-read"

  versioning = {
    enabled = true
  }

  website = {
    index_document = "reports.js"
  }

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${module.reports_site_bucket.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

module "billing_site_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "billing-page-innovatehk"
  acl    = "public-read"

  versioning = {
    enabled = true
  }

  website = {
    index_document = "billing.js"
  }

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${module.billing_site_bucket.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

module "design_site_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "design-page-innovatehk"
  acl    = "public-read"

  versioning = {
    enabled = true
  }

  website = {
    index_document = "design.js"
  }

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${module.design_site_bucket.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

resource "aws_acm_certificate" "innovatehk_cert" {
  domain_name       = "innovatehk.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_zone" "innovatehk_route53_zone_new" {
  name         = "innovatehk.com"
}

resource "aws_route53_record" "innovatehk_route53_dns" {
  allow_overwrite = true
  name =  tolist(aws_acm_certificate.innovatehk_cert.domain_validation_options)[0].resource_record_name
  records = [tolist(aws_acm_certificate.innovatehk_cert.domain_validation_options)[0].resource_record_value]
  type = tolist(aws_acm_certificate.innovatehk_cert.domain_validation_options)[0].resource_record_type
  zone_id = aws_route53_zone.innovatehk_route53_zone_new.zone_id
  ttl = 60
}

# resource "aws_acm_certificate_validation" "innovatehk_cert_validation" {
#   certificate_arn = aws_acm_certificate.innovatehk_cert.arn
#   validation_record_fqdns = [aws_route53_record.innovatehk_route53_dns.fqdn]
# }


module "cdn_main" {
  source = "cloudposse/cloudfront-s3-cdn/aws"
  version = "0.86.0"
  name                          = "innovatehk"
  stage                         = null
  namespace                     = null

//  origin_bucket                       = module.main_site_bucket.s3_bucket_id
  origin_bucket                       = "main-site-innovatehk"
  aliases                             = ["main.innovatehk.com"]
  dns_alias_enabled                   = true
  parent_zone_name                    = aws_route53_zone.innovatehk_route53_zone_new.name
  allowed_methods                     = ["HEAD", "GET"]
  cached_methods                      = ["HEAD", "GET"]
  cloudfront_access_logging_enabled   = false
}

//-------------------------------------------
// Network
//-------------------------------------------

resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "VPC-Fargate"
  }
}

resource "aws_subnet" "public_fargate_subnet" {
  count = 2

  cidr_block = cidrsubnet(aws_vpc.main_vpc.cidr_block, 8, count.index)
  vpc_id     = aws_vpc.main_vpc.id

  tags = {
    Name = "public-fargate-subnet-${count.index}"
  }
}

resource "aws_subnet" "private_db_subnet" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = cidrsubnet(aws_vpc.main_vpc.cidr_block, 8, 3)

  tags = {
    Name = "private-db-subnet"
  }
}


//-------------------------------------------
// Backend API
//-------------------------------------------


resource "aws_security_group" "api" {
  name        = "allow_public_access"
  description = "Allow public access to web server"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "fargate_api_cluster" {
  name = "Fargate-API-Cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "api" {
  family = "api-task"
  requires_compatibilities = ["FARGATE"]
  network_mode = "awsvpc"
  cpu = 1024
  memory = 2048

  container_definitions = jsonencode([
    {
      name: "api",
      image: "node:14-alpine",
      portMappings: [
        {
          containerPort: 80,
          hostPort: 80
        }
      ],
      essential: true,
      command: [
        "node",
        "server.js"
      ]
    }
  ])
}

resource "aws_ecs_service" "api" {
  name            = "api-service"
  task_definition = aws_ecs_task_definition.api.arn
  cluster         = aws_ecs_cluster.fargate_api_cluster.id
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.public_fargate_subnet.*.id
    security_groups = [aws_security_group.api.id]
    assign_public_ip = true
  }
}


//-------------------------------------------
// Database
//-------------------------------------------

resource "aws_security_group" "postgresql_rds_sg" {
  name        = "postgresql-rds-security-group"
  description = "Security group for PostgreSQL RDS database"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = "dev"
  }
}

resource "aws_db_instance" "postgresql_rds" {
  identifier              = "postgresqlrds"
  engine                  = "postgres"
  engine_version          = "14.6"
  instance_class          = "db.t3.medium"
  db_name                 = "postgresqldb"
  username                = "innovatehkadmin"
  password                = "secretpassword"
  allocated_storage       = 20
  storage_type            = "gp3"
  vpc_security_group_ids  = [ aws_security_group.postgresql_rds_sg.id ]

  tags = {
    Environment = "dev"
  }
}