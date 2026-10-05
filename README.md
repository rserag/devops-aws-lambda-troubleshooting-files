# AWS Lambda and Terraform Troubleshooting

This fork fixes the deployment package, S3 configuration, Lambda runtime, handler behavior and execution permissions in the original project.

The AWS provider configuration remains unchanged: `us-east-1`. Only the existing AWS services—Lambda, S3 and IAM—are used.

## Changes

| Issue | Fix |
| --- | --- |
| Lambda referenced an S3 ZIP that the project never uploaded | Added a Terraform-managed S3 object for the deployment package |
| Package changes were not tracked | Added an S3 source hash and Lambda source-code hash |
| Fixed bucket name risked global name collisions | Used a generated bucket name with a stable prefix |
| Bucket used a deprecated inline ACL | Removed the ACL, disabled ACLs through ownership controls, and explicitly blocked public access |
| Python 3.8 was deprecated | Updated Lambda to Python 3.12 |
| Handler returned a greeting without storing data | Handler now writes the incoming JSON event to S3 |
| Execution role had no S3 permissions | Added permission for `s3:PutObject` only under the bucket’s `data/` prefix |
| Dependencies were not packaged | Included Boto3 and its dependencies in the ZIP |

The original Lambda trust policy was valid and is retained.

## Prerequisites

- Terraform.
- AWS CLI configured with deployment permissions.
- Python 3 with pip.
- `zip`.
- Access to PyPI when building the package.

Terraform uses local state. State files, saved plans, downloaded dependencies and generated artifacts are excluded from Git. Keep the local state available for future updates and cleanup.

## Build

From a fresh checkout:

```bash
mkdir package

python3 -m pip install \
  --requirement requirements.txt \
  --target package \
  --platform manylinux2014_x86_64 \
  --implementation cp \
  --python-version 3.12 \
  --only-binary=:all: \
  --no-compile

cp handler.py package/
cd package
zip -r ../lambda_function_payload.zip .
cd ..
```

The ZIP contains `handler.py` and its dependencies at the archive root. Dependencies target Linux x86_64 and Python 3.12.

Rebuild the package after changing the handler or dependencies.

## Deploy

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan -out=task3.tfplan
terraform apply task3.tfplan
```

The initial deployment creates seven resources.

Terraform uploads the package before creating Lambda. The function receives the bucket name through its `BUCKET_NAME` environment variable.

## Test

Wait for Lambda to become active:

```bash
aws lambda wait function-active-v2 \
  --region us-east-1 \
  --function-name my_lambda
```

Invoke it:

```bash
aws lambda invoke \
  --region us-east-1 \
  --function-name my_lambda \
  --cli-binary-format raw-in-base64-out \
  --payload '{"message":"task3-test"}' \
  response.json

cat response.json
```

Check that invocation metadata has no `FunctionError`. The response should contain `statusCode: 200` and a JSON body identifying the bucket and object key.

Read the stored object:

```bash
TASK3_BUCKET=$(python3 -c 'import json; print(json.loads(json.load(open("response.json"))["body"])["bucket"])')
TASK3_KEY=$(python3 -c 'import json; print(json.loads(json.load(open("response.json"))["body"])["key"])')

aws s3 cp "s3://${TASK3_BUCKET}/${TASK3_KEY}" - \
  --region us-east-1
```

Expected contents:

```json
{"message":"task3-test"}
```

Each invocation writes to `data/<AWS-request-ID>.json`. Separate invocations produce separate objects.

## Idempotence

After deployment, run:

```bash
terraform plan
```

Expected: `No changes`.

Terraform retains the generated bucket name in state. Package hashes trigger updates when the ZIP changes.

## Verification Performed

- Terraform formatting and validation passed without warnings.
- ZIP integrity, handler contents and packaged dependencies were checked.
- A local handler test using the packaged SDK verified the expected S3 request and response.
- Terraform applied successfully.
- A real Lambda invocation returned success.
- The resulting S3 object contained the exact test event.
- The object had JSON content type and AES256 encryption.
- Lambda reported an active state and successful update.
- A subsequent Terraform plan reported no changes.

## Permissions and Cleanup

The execution role can write only to the bucket’s `data/` prefix. It cannot list, read or delete objects, or overwrite the deployment ZIP. CloudWatch log permissions are not enabled; execution was verified through the invocation response and stored object.

The bucket has `force_destroy = false`. Generated `data/` objects are not managed by Terraform and will prevent bucket deletion. If cleanup is intended, remove those objects before running `terraform destroy`.
