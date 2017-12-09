variable "project" { default = "example" }
variable "AWS_REGION" { default = "us-east-1" }
variable "AWS_ACCOUNT_ID" {}
variable "AWS_ACCESS_KEY" {}
variable "AWS_SECRET_KEY_ID" {}

provider "aws" {
  access_key = "${var.AWS_ACCESS_KEY}"
  secret_key = "${var.AWS_SECRET_KEY_ID}"
  region     = "${var.AWS_REGION}"
}

resource "aws_s3_bucket" "jar_bucket" {
  bucket = "${var.project}-jars"
  acl    = "private"
}

resource "aws_s3_bucket_object" "jar_file" {
  bucket = "${var.project}-jars"
  depends_on = ["aws_s3_bucket.jar_bucket"]
  key    = "example.jar"
  source = "../target/example.jar"
  etag   = "${md5(file("../target/example.jar"))}"
}

resource "aws_iam_policy" "lambda-policy" {
  name        = "${var.project}-lambda-policy"
  path        = "/"
  description = "Lambda execution policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:logs:${var.AWS_REGION}:*:*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "lambda-role" {
  name = "${var.project}-lambda-assume-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": "1"
    }
  ]
}
EOF
}


resource "aws_iam_policy_attachment" "lambda-role-policy-attach" {
  name = "${var.project}-lambda-role-policy-attach"
  roles = ["${aws_iam_role.lambda-role.name}"]
  policy_arn = "${aws_iam_policy.lambda-policy.arn}"
}


resource "aws_lambda_function" "example_lambda" {
  depends_on = ["aws_s3_bucket.jar_bucket",
                "aws_iam_role.lambda-role",
                "aws_s3_bucket_object.jar_file",
                "aws_iam_policy.lambda-policy"]
  s3_bucket          = "${aws_s3_bucket.jar_bucket.bucket}"
  s3_key             = "example.jar"
  function_name      = "${var.project}-lambda"
  description        = "An example API for a new day"
  role               = "${aws_iam_role.lambda-role.arn}"
  handler            = "example.core.LambdaFunction"
  source_code_hash = "${base64sha256(file("..//target/example.jar"))}"
  runtime            = "java8"
  timeout            = 100
  memory_size        = 256
}


resource "aws_lambda_permission" "handler_apigateway_permission" {
  function_name = "${aws_lambda_function.example_lambda.arn}"
  action = "lambda:InvokeFunction"
  statement_id = "AllowExecutionFromApiGateway"
  principal = "apigateway.amazonaws.com"
}


resource "aws_api_gateway_rest_api" "proxy" {
  name = "example-proxy"
}


resource "aws_api_gateway_method" "proxy_root_methods" {
  http_method = "ANY"
  authorization = "NONE"
  rest_api_id = "${aws_api_gateway_rest_api.proxy.id}"
  resource_id = "${aws_api_gateway_rest_api.proxy.root_resource_id}"
}


resource "aws_api_gateway_integration" "proxy_root_handler_integration" {
  type = "AWS_PROXY"
  integration_http_method = "POST"
  rest_api_id = "${aws_api_gateway_rest_api.proxy.id}"
  resource_id = "${aws_api_gateway_rest_api.proxy.root_resource_id}"
  http_method = "${aws_api_gateway_method.proxy_root_methods.http_method}"
  uri = "arn:aws:apigateway:${var.AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.AWS_REGION}:${var.AWS_ACCOUNT_ID}:function:${aws_lambda_function.example_lambda.function_name}/invocations"
}


resource "aws_api_gateway_resource" "proxy_greedy_resource" {
  rest_api_id = "${aws_api_gateway_rest_api.proxy.id}"
  parent_id = "${aws_api_gateway_rest_api.proxy.root_resource_id}"
  path_part = "{proxy+}"
}


resource "aws_api_gateway_method" "proxy_greedy_methods" {
  http_method = "ANY"
  authorization = "NONE"
  rest_api_id = "${aws_api_gateway_rest_api.proxy.id}"
  resource_id = "${aws_api_gateway_resource.proxy_greedy_resource.id}"
}


resource "aws_api_gateway_integration" "proxy_greedy_handler_integration" {
  type = "AWS_PROXY"
  integration_http_method = "POST"
  rest_api_id = "${aws_api_gateway_rest_api.proxy.id}"
  resource_id = "${aws_api_gateway_resource.proxy_greedy_resource.id}"
  http_method = "${aws_api_gateway_method.proxy_greedy_methods.http_method}"
  uri = "arn:aws:apigateway:${var.AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.AWS_REGION}:${var.AWS_ACCOUNT_ID}:function:${aws_lambda_function.example_lambda.function_name}/invocations"
}


resource "aws_api_gateway_deployment" "proxy_deployment" {
  rest_api_id= "${aws_api_gateway_rest_api.proxy.id}"
  stage_name = "production"
  variables = {}
  depends_on = [
    "aws_api_gateway_integration.proxy_root_handler_integration",
    "aws_api_gateway_integration.proxy_greedy_handler_integration",
  ]
}


resource "aws_iam_role" "handler_role" {
  name = "example-proxy-handler"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "sts:AssumeRole"
      ],
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
  EOF
}


# Keep Lambda "warm" to make startup much faster:
resource "aws_cloudwatch_event_rule" "example_5min_rule" {
    name = "example-every-five-minutes"
    description = "Fires Example lambda every five minutes"
    schedule_expression = "rate(5 minutes)"
}


resource "aws_lambda_permission" "cw_event_call_example_lambda" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.example_lambda.function_name}"
    principal = "events.amazonaws.com"
    source_arn = "${aws_cloudwatch_event_rule.example_5min_rule.arn}"
}


resource "aws_cloudwatch_event_target" "target5min" {
    rule = "${aws_cloudwatch_event_rule.example_5min_rule.name}"
    target_id = "example_lambda"
    arn = "${aws_lambda_function.example_lambda.arn}"
}


output "url" {
  value = "${aws_api_gateway_deployment.proxy_deployment.invoke_url}"
}
