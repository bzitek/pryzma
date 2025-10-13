 resource "aws_lambda_function" "analysis_lambda" {
   filename      = "resources/lambda_function_payload.zip"
   function_name = "${local.resource_prefix.value}-analysis"
   role          = "${aws_iam_role.iam_for_lambda.arn}"
   handler       = "exports.test"
 
   source_code_hash = "${filebase64sha256("resources/lambda_function_payload.zip")}"
 
-  runtime = "nodejs12.x"
-
-  environment {
-    variables = {
-      access_key = "AKIAIOSFODNN7EXAMPLE"
-      secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
-    }
-  }
+  runtime = "nodejs12.x"  # (Security note: Node.js 12 is EOL; upgrade when you can)
+
+  # ✅ Remove access_key/secret_key – let Lambda use its execution role.
+  # environment { variables = { } }  # (optional) keep only NON-sensitive values
