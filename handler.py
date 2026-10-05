import json
import os

import boto3

s3 = boto3.client("s3")


def handler(event, context):
    bucket = os.environ["BUCKET_NAME"]
    key = f"data/{context.aws_request_id}.json"

    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(event).encode("utf-8"),
        ContentType="application/json",
    )

    return {
        "statusCode": 200,
        "body": json.dumps({"bucket": bucket, "key": key}),
    }