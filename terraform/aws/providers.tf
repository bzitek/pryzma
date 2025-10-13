--- a/terraform/aws/providers.tf
+++ b/terraform/aws/providers.tf
@@
 provider "aws" {
   profile = var.profile
   region  = var.region
 }
 
-# ❌ DO NOT hard-code long-term credentials
-provider "aws" {
-  alias       = "plain_text_access_keys_provider"
-  region      = "us-west-1"
-  access_key  = "AKIAIOSFODNN7EXAMPLE"
-  secret_key  = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
-}
+## ✅ Use the default credential chain (recommended):
+## - EC2/ECS/Lambda: IAM Role / Instance Profile
+## - CI (GitHub Actions): OIDC → STS AssumeRole
+## - Local dev: named profile / SSO
+## If you need a second provider, configure `assume_role` (no long-term keys).
+# provider "aws" {
+#   alias  = "workload"
+#   region = "us-west-1"
+#   assume_role {
+#     role_arn     = var.workload_role_arn
+#     session_name = "tf-workload"
+#   }
+# }
