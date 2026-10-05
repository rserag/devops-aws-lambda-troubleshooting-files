provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "my_bucket" {
  bucket_prefix = "devops-lambda-"
}

resource "aws_s3_bucket_ownership_controls" "my_bucket" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "my_bucket" {
  bucket = aws_s3_bucket.my_bucket.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_lambda_function" "my_lambda" {
  function_name = "my_lambda"

  s3_bucket        = aws_s3_object.lambda_package.bucket
  s3_key           = aws_s3_object.lambda_package.key
  source_code_hash = filebase64sha256("${path.module}/lambda_function_payload.zip")

  handler = "handler.handler"
  runtime = "python3.12"
  timeout = 10
  role    = aws_iam_role.iam_for_lambda.arn
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.my_bucket.id
    }
  }

  depends_on = [aws_iam_role_policy.lambda_s3_write]
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_s3_write" {
  name = "lambda-s3-write"
  role = aws_iam_role.iam_for_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.my_bucket.arn}/data/*"
    }]
  })
}

resource "aws_s3_object" "lambda_package" {
  bucket       = aws_s3_bucket.my_bucket.id
  key          = "lambda_function_payload.zip"
  source       = "${path.module}/lambda_function_payload.zip"
  source_hash  = filemd5("${path.module}/lambda_function_payload.zip")
  content_type = "application/zip"
}
