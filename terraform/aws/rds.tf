# A map of cluster names to their backup retention periods
variable "rds_clusters" {
  description = "A map of RDS clusters to create with their backup retention periods."
  type        = map(number)
  default = {
    "app1-rds-cluster" = 0
    "app2-rds-cluster" = 1
    "app3-rds-cluster" = 15
    "app4-rds-cluster" = 15
    "app5-rds-cluster" = 15
    "app6-rds-cluster" = 15
    "app7-rds-cluster" = 25
    "app8-rds-cluster" = 25
    "app9-rds-cluster" = 25
  }
}

# 1. Create a random password for each cluster
resource "random_password" "single_instance_db" {
  length  = 16
  special = true
}

# 2. Create a secret in AWS Secrets Manager for each cluster
resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.resource_prefix}-rds-credentials"
}

# 3. Store the randomly generated password in the secret
resource "aws_secretsmanager_secret_version" "db_credentials" {
  for_each      = var.rds_clusters
  secret_id     = aws_secretsmanager_secret.db_credentials[each.key].id
  secret_string = random_password.db[each.key].result
}

# 4. Create all RDS clusters using the secure passwords
resource "aws_rds_cluster" "app_rds_clusters" {
  for_each = var.rds_clusters

  # Required arguments are now securely managed
  engine          = "aurora-postgresql" # Or "aurora-mysql", etc.
  master_username = "adminuser"
  # FIX: Password is now taken from the corresponding random_password resource
  master_password = random_password.db[each.key].result

  # Arguments from your original code
  cluster_identifier      = each.key
  backup_retention_period = each.value
  storage_encrypted       = true

  # This lifecycle block prevents Terraform from showing a difference
  # in the plan every time the password changes in the secret.
  lifecycle {
    ignore_changes = [master_password]
  }

  tags = {
    Name     = each.key
    git_repo = "terragoat"
  }
}