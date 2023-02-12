terraform {
  required_version = ">= 0.12"
  required_providers {
    aws ={
        source="hashicorp/aws"
        version=">=4.53"
    }
  }
}
variable aws_region {
  type        = string
  default     = "us-east-1"
  description = "region"
}
variable aws_account {
  type    = string
  default = "385301451600"
  description = "aws_account"
}
provider "aws"{
region=var.aws_region
} 
//provider "account"{
//accountId=var.aws_account
//}
data "archive_file" "myzip" {
  type        = "zip"
  source_file="calcTera.py"
  output_path = "calcTera.zip"
}

data "archive_file" "myzip1" {
  type        = "zip"
  source_file="calcSetBoundries.py"
  output_path = "calcSetBoundries.zip"

}
data "archive_file" "tenant" {
  type        = "zip"
  source_file="calc_tenant_authorizer.py"
  output_path = "calc_tenant_authorizer.zip"
}
# Variables
//variable "myregion" {}
//myregion="us-east-1"
//variable "accountId" {}
//accountId="385301451600"

resource "aws_dynamodb_table" "calcboundries" { 
   name = "calcboundries" 
   billing_mode = "PROVISIONED" 
   read_capacity = "30" 
   write_capacity = "30" 
   attribute { 
      name = "name" 
      type = "S" 
   }
   attribute{
      name = "mode"
      type = "S"
   } 
   range_key="mode"
   hash_key = "name" 
   ttl { 
     enabled = true
     attribute_name = "expiryPeriod"  
   }
   point_in_time_recovery { enabled = true } 
   server_side_encryption { enabled = true } 
   lifecycle { ignore_changes = [ "write_capacity", "read_capacity" ] }
} 

resource "aws_lambda_function" "calcTeraform" {
    filename="calcTera.zip"
    function_name="calcTeraform"
    role=aws_iam_role.iam_for_lambda.arn
    handler="calcTera.lambda_handler"
    runtime="python3.8"
}

resource "aws_lambda_function" "calc_tenant_authorizer" {
    filename="calc_tenant_authorizer.zip"
    function_name="calc_tenant_authorizer"
    role=aws_iam_role.iam_for_lambda.arn
    handler="calc_tenant_authorizer.lambda_handler"
    runtime="python3.8"
    layers=["arn:aws:lambda:us-east-1:580247275435:layer:LambdaInsightsExtension:21"]

}

#add Lambda Layer
resource "aws_lambda_layer_version" "lambda_layer" {
  filename   = "calc_tenant_authorizer.zip"
  layer_name = "LambdaInsightsExtension"
  compatible_runtimes = ["nodejs16.x"]
}

resource "aws_iam_role" "iam_for_lambda"{
    name="calcLambdaRole"
    assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
        Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_lambda_function" "calcSetBoundries" {
    filename="calcSetBoundries.zip"
    function_name="calcSetBoundries"
    role=aws_iam_role.iam_for_calc.arn
    handler="calcSetBoundries.lambda_handler"
    runtime="python3.8"
}
resource "aws_iam_role" "iam_for_calc"{
    name="calcSetBoundries"
    assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
        Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
   role = aws_iam_role.iam_for_lambda.name
   for_each = toset([
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
   ])
     policy_arn = each.value
}


resource "aws_iam_role_policy_attachment" "lambda_policy1" {
   role = aws_iam_role.iam_for_calc.name
   for_each = toset ([
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
   ])
   policy_arn = each.value
}

resource "aws_iam_role" "api_gateway_account_role" {
  name = "api-gateway-account-role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "apigateway.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_account_role.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ],
        "Resource" : "*"
      }
    ]
  })
}
resource "aws_api_gateway_account" "api_gateway_account" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_account_role.arn
}
#Apis example https://gist.github.com/mendhak/8303d60cbfe8c9bf1905def3ccdb2176

resource "aws_api_gateway_rest_api" "calcTotalEffort" {
  body = jsonencode({
    openapi = "3.0.1"
    info = {
      title   = "calcTotalEffort"
      version = "1.0"
    }
    paths = {
      "/path1" = {
        get = {
          x-amazon-apigateway-integration = {
            httpMethod           = "GET"
            payloadFormatVersion = "1.0"
            type                 = "HTTP_PROXY"
            uri                  = "https://ip-ranges.amazonaws.com/ip-ranges.json"
          }
        }
      }
    }
  })
  //role= aws_api_gateway_account.api_gateway_account
  name = "calcTotalEffort"
}

resource "aws_api_gateway_deployment" "calcTotalEffort" {
  rest_api_id = aws_api_gateway_rest_api.calcTotalEffort.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.calcTotalEffort.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "calcTotalEffort" {
  deployment_id = aws_api_gateway_deployment.calcTotalEffort.id
  rest_api_id   = aws_api_gateway_rest_api.calcTotalEffort.id
  stage_name    = "calcTotalEffort"
  //role= aws_api_gateway_account.api_gateway_account


}
#Terraform Resources
/*resource "aws_api_gateway_rest_api" "calcTotalEffort" {
  name = "calcTotalEffort"
}*/

resource "aws_api_gateway_resource" "resource" {
  parent_id   = aws_api_gateway_rest_api.calcTotalEffort.root_resource_id
  path_part   = "{proxy+}"
  rest_api_id = aws_api_gateway_rest_api.calcTotalEffort.id
}

resource "aws_api_gateway_method" "calcTotalEffort" {
  authorization = "NONE"
  http_method   = "PUT"
  resource_id   = aws_api_gateway_resource.resource.id
  rest_api_id   = aws_api_gateway_rest_api.calcTotalEffort.id
  //role= aws_api_gateway_account.api_gateway_account
  request_parameters = {
    "method.request.path.proxy" = true
    "method.request.querystring.custName"="true"
    "method.request.querystring.oppurtunity"="true"
    "method.request.querystring.rearchitectLargeApp"="true"
    "method.request.querystring.rearchitectMediumApp"="true"
    "method.request.querystring.rearchitectSmallApp"="true"
    "method.request.querystring.refactorApp"="true" 
    "method.request.querystring.refactorLargeApp"="true" 
    "method.request.querystring.refactorMediumApp"="true" 
    "method.request.querystring.refactorSmallApp"="true" 
    "method.request.querystring.rehost"="true" 
    "method.request.querystring.rehostLargeApp"="true" 
    "method.request.querystring.rehostMediumApp"="true" 
    "method.request.querystring.rehostSmallApp"="true" 
    "method.request.querystring.replatformLargeApp"="true" 
    "method.request.querystring.replatformSmallApp"="true" 
    

  }
}

/*resource "aws_api_gateway_integration" "calcTotalEffort" {
  http_method = aws_api_gateway_method.calcTotalEffort.http_method
  resource_id = aws_api_gateway_resource.resource.id
  rest_api_id = aws_api_gateway_rest_api.calcTotalEffort.id
  type        = "MOCK"
}*/

/*resource "aws_api_gateway_deployment" "calcTotalEffort" {
  rest_api_id = aws_api_gateway_rest_api.calcTotalEffort.id

  triggers = {
    # NOTE: The configuration below will satisfy ordering considerations,
    #       but not pick up all future REST API changes. More advanced patterns
    #       are possible, such as using the filesha1() function against the
    #       Terraform configuration file(s) or removing the .id references to
    #       calculate a hash against whole resources. Be aware that using whole
    #       resources will show a difference after the initial implementation.
    #       It will stabilize to only change when resources change afterwards.
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.calcTotalEffort.id,
      aws_api_gateway_method.calcTotalEffort.id,
      aws_api_gateway_integration.calcTotalEffort.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

/*resource "aws_api_gateway_stage" "calcTotalEffort" {
  deployment_id = aws_api_gateway_deployment.calcTotalEffort.id
  rest_api_id   = aws_api_gateway_rest_api.calcTotalEffort.id
  stage_name    = "calcTotalEffort"
}*/

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.calcTotalEffort.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.calcTotalEffort.http_method
  integration_http_method = "PUT"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.calcTeraform.invoke_arn
  #uri                  = "https://httpbin.org/anything/{proxy}"
 /* request_parameters = {
    #depends_on = [time_sleep.wait_30_seconds]

    "integration.request.path.proxy" = "method.request.path.proxy"
    "integration.request.mappingtemplate.calcEffort"="calcEffort"
  } */    
}
/*resource "aws_api_gateway_integration" "urlinput" {
  depends_on  = [aws_api_gateway_integration.integration]
  integration_http_method = "ANY"
  rest_api_id             = aws_api_gateway_rest_api.calcTotalEffort.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.calcTotalEffort.http_method
  type                    = "HTTP_PROXY"
  #uri                     = aws_lambda_function.calcTeraform.invoke_arn
  uri                     = "https://httpbin.org/anything/{proxy}"

  #urlinput.request.path.proxy=true
  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
    "aws_api_gateway_integration.integration.request.querystring.calcEffort"="integration_http_method.request.querystring.calcEffort"
    "urlinput.request.querystring.oppurtunity"="integration_http_method.request.querystring.oppurtunity"
    "urlinput.request.querystring.rehost"="integration_http_method.request.querystring.rehost"
    "urlinput.request.querystring.rehostLargeApp"="integration_http_method.request.querystring.rehostLargeApp"
    "urlinput.request.querystring.rehostMediumApp"="integration_http_method.request.querystring.rehostMediumApp"
    "urlinput.request.querystring.rehostSmallApp"="integration_http_method.request.querystring.rehostSmallApp" 
        }
} 
}*/
resource "aws_api_gateway_deployment" "teststage" {
  depends_on = [
    aws_api_gateway_integration.integration
  ]
  rest_api_id = aws_api_gateway_rest_api.calcTotalEffort.id
  stage_name  = "test"
}
# Lambda
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.calcTeraform.function_name
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:${var.aws_region}:${var.aws_account}:${aws_api_gateway_rest_api.calcTotalEffort.id}/*/${aws_api_gateway_method.calcTotalEffort.http_method}${aws_api_gateway_resource.resource.path}"
}

/*resource "aws_lambda_function" "lambda" {
  filename      = "lambda.zip"
  function_name = "mylambda"
  role=aws_iam_role.iam_for_lambda.arn
  handler       = "lambda.lambda_handler"
  runtime       = "python3.7"

 # source_code_hash = filebase64sha256("lambda.zip")
}

# IAM
resource "aws_iam_role" "role" {
  name = "myrole"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
      ]
}
POLICY
} */
#add authorizer to API
resource "aws_api_gateway_authorizer" "authorizer" {
  name                   = "authorizer"
  rest_api_id = aws_api_gateway_rest_api.calcTotalEffort.id
  authorizer_uri         = aws_lambda_function.calc_tenant_authorizer.invoke_arn
  authorizer_credentials = aws_iam_role.api_gateway_account_role.arn
}
/*resource "aws_lambda_function" "authorizer" {
  filename      = "calc_tenant_authorizer.zip"
  function_name = "calc_tenant_authorizer"
  runtime = "python3.9"
  //role          = aws_iam_role.lambda.arn
  role=aws_iam_role.iam_for_lambda.arn
  handler="calc_tenant_authorizer.lambda_handler"
  source_code_hash = filebase64sha256("calc_tenant_authorizer.zip")
}*/

