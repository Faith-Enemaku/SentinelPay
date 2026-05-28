package terraform.security

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_iam_access_key"
  not is_delete(rc)

  msg := sprintf("Do not create IAM access keys with Terraform because secrets are stored in state: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_secretsmanager_secret_version"
  not is_delete(rc)
  rc.change.after.secret_string != null

  msg := sprintf("Do not place plaintext secret_string values in Terraform-managed secret versions: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_cloudtrail"
  not is_delete(rc)
  rc.change.after.enable_log_file_validation != true

  msg := sprintf("CloudTrail must enable log file validation: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_cloudtrail"
  not is_delete(rc)
  rc.change.after.is_multi_region_trail != true

  msg := sprintf("CloudTrail must be multi-region for account-wide audit coverage: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_s3_bucket_public_access_block"
  not is_delete(rc)

  pab := rc.change.after
  pab.block_public_acls != true

  msg := sprintf("S3 bucket public ACL blocking must be enabled: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_s3_bucket_public_access_block"
  not is_delete(rc)

  pab := rc.change.after
  pab.block_public_policy != true

  msg := sprintf("S3 bucket public policy blocking must be enabled: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_s3_bucket_public_access_block"
  not is_delete(rc)

  pab := rc.change.after
  pab.ignore_public_acls != true

  msg := sprintf("S3 bucket must ignore public ACLs: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_s3_bucket_public_access_block"
  not is_delete(rc)

  pab := rc.change.after
  pab.restrict_public_buckets != true

  msg := sprintf("S3 bucket must restrict public buckets: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_s3_bucket_acl"
  not is_delete(rc)

  acl := rc.change.after.acl
  acl == "public-read"

  msg := sprintf("S3 public-read ACL is not allowed: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_s3_bucket_acl"
  not is_delete(rc)

  acl := rc.change.after.acl
  acl == "public-read-write"

  msg := sprintf("S3 public-read-write ACL is not allowed: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_db_instance"
  not is_delete(rc)

  rc.change.after.publicly_accessible == true

  msg := sprintf("RDS instances must not be publicly accessible: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_db_instance"
  not is_delete(rc)

  rc.change.after.storage_encrypted != true

  msg := sprintf("RDS storage encryption must be enabled: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_security_group"
  not is_delete(rc)

  ingress := rc.change.after.ingress[_]
  cidr := ingress.cidr_blocks[_]
  cidr == "0.0.0.0/0"

  sensitive_port(ingress.from_port)

  msg := sprintf("Security group exposes sensitive port %v to the internet: %s", [ingress.from_port, rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_security_group"
  not is_delete(rc)

  ingress := rc.change.after.ingress[_]
  cidr := ingress.cidr_blocks[_]
  cidr == "0.0.0.0/0"
  ingress.protocol == "-1"

  msg := sprintf("Security group allows all protocols from the internet: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.mode == "managed"
  rc.type == "aws_security_group_rule"
  not is_delete(rc)

  rc.change.after.type == "ingress"
  cidr := rc.change.after.cidr_blocks[_]
  cidr == "0.0.0.0/0"

  sensitive_port(rc.change.after.from_port)

  msg := sprintf("Security group rule exposes sensitive port %v to the internet: %s", [rc.change.after.from_port, rc.address])
}

sensitive_port(port) {
  port == 22
}

sensitive_port(port) {
  port == 3306
}

sensitive_port(port) {
  port == 5432
}

sensitive_port(port) {
  port == 6379
}

sensitive_port(port) {
  port == 9200
}

sensitive_port(port) {
  port == 5000
}

sensitive_port(port) {
  port == 5001
}

sensitive_port(port) {
  port == 5002
}

is_delete(rc) {
  rc.change.actions == ["delete"]
}