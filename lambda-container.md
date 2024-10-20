# Running unbound and open-mpic inside AWS lambda container

This is an experiment for running open-mpic code alongside [unbound](https://github.com/NLnetLabs/unbound) as a container inside AWS lambda functions.
> [!IMPORTANT]
> This version of open-mpic is not using or interacting with unbound python bindings and only mpic_ccordinator code running as a function inside the container.
Check [unbound python bindings documentation](https://unbound.docs.nlnetlabs.nl/en/latest/developer/python-modules.html#pyunbound) for the usage.

1. Build docker image

`docker build  --platform linux/amd64 -t mpic-lambda-container:latest .`

2. Login AWS ECR to push image with docker

`aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <AWS-ACCOUNT-ID>.dkr.ecr.<REGION>.amazonaws.com`

3. Create repository

`aws ecr create-repository --repository-name open-mpic-lambda --region <REGION> --image-scanning-configuration scanOnPush=false --image-tag-mutability MUTABLE`

As a successful response you should get json response with repository configuration, arn and URL. Example:
```json
{
    "repository": {
        "repositoryArn": "arn:aws:ecr:<REGION>:<AWS-ACCOUNT-ID>:repository/open-mpic-lambda",
        "registryId": "<AWS-ACCOUNT-ID>",
        "repositoryName": "open-mpic-lambda",
        "repositoryUri": "<AWS-ACCOUNT-ID>.dkr.ecr.<REGION>.amazonaws.com/open-mpic-lambda",
        "createdAt": "2024-10-20T20:22:49.374000+02:00",
        "imageTagMutability": "MUTABLE",
        "imageScanningConfiguration": {
            "scanOnPush": false
        },
        "encryptionConfiguration": {
            "encryptionType": "AES256"
        }
    }
}
```

4. Tag your local image into ECR repository. Copy `repositoryUri` from previous response.

`docker tag mpic-lambda-container:latest <ECR-REPOSITORY-URL>:latest`

5. Push the image.

`docker push <ECR-REPOSITORY-URL>:latest`

6. If you have execution role for the function skip this step, otherwise create a role with least permissions:

```sh
aws iam create-role \
  --role-name open-mpic-lambda-role \
  --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}'
  ```

  You should see the following output:

  ```json
  {
      "Role": {
          "Path": "/",
          "RoleName": "open-mpic-lambda-role",
          "RoleId": "<ROLE-ID>",
          "Arn": "arn:aws:iam::<AWS-ACCOUNT-ID>:role/open-mpic-lambda-role",
          "CreateDate": "2024-10-20T18:44:00+00:00",
          "AssumeRolePolicyDocument": {
              "Version": "2012-10-17",
              "Statement": [
                  {
                      "Effect": "Allow",
                      "Principal": {
                          "Service": "lambda.amazonaws.com"
                      },
                      "Action": "sts:AssumeRole"
                  }
              ]
          }
      }
  }
```

7. Create lambda function. Use image id from step 5 and role `Arn` from the response at step 6.

```sh
aws lambda create-function \
  --function-name open-mpic-container \
  --package-type Image \
  --code ImageUri=<AWS-ACCOUNT-ID>.dkr.ecr.<REGION>.amazonaws.com/open-mpic-lambda:latest \
  --role arn:aws:iam::<AWS-ACCOUNT-ID>:role/open-mpic-lambda-role
```

Example response:

```json
{
    "FunctionName": "open-mpic-container",
    "FunctionArn": "arn:aws:lambda:<REGION>:<AWS-ACCOUNT-ID>:function:open-mpic-container",
    "Role": "arn:aws:iam::<AWS-ACCOUNT-ID>:role/open-mpic-lambda-role",
    "CodeSize": 0,
    "Description": "",
    "Timeout": 3,
    "MemorySize": 128,
    "LastModified": "2024-10-20T18:54:50.634+0000",
    "CodeSha256": "",
    "Version": "$LATEST",
    "TracingConfig": {
        "Mode": "PassThrough"
    },
    "RevisionId": "",
    "State": "Pending",
    "StateReason": "The function is being created.",
    "StateReasonCode": "Creating",
    "PackageType": "Image",
    "Architectures": [
        "x86_64"
    ],
    "EphemeralStorage": {
        "Size": 512
    },
    "SnapStart": {
        "ApplyOn": "None",
        "OptimizationStatus": "Off"
    }
}
```

You can run function from AWS Console with test event.

## Clean up
1. Delete lambda function:
```sh
aws lambda delete-function \
--function-name open-mpic-container
```
2. Delete the image and repository:

Delete image:
```sh
aws ecr batch-delete-image \
     --repository-name open-mpic-lambda \
     --image-ids imageTag=latest
```

Delete repository:
```sh
aws ecr delete-repository \
    --repository-name open-mpic-lambda \
    --force
```

3. Delete IAM role

```sh
aws iam delete-role \
    --role-name open-mpic-lambda-role
```

> [!TIP]
> Docs for further reading
> * https://docs.aws.amazon.com/lambda/latest/dg/python-image.html
> * https://unbound.docs.nlnetlabs.nl/en/latest/developer/python-modules.html#pyunbound
> * https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html#permissions-executionrole-api


## (BONUS) Example lambda function calling unbound for dns resolving
1. Create simple `lambda_function.py` file and add the following code

```python
import sys
import unbound
def handler(event, context):
    print(event['domain'])
    ctx = unbound.ub_ctx()
    ctx.resolvconf("/etc/resolv.conf")
    status, result = ctx.resolve(event['domain'], unbound.RR_TYPE_A, unbound.RR_CLASS_IN)
    if status==0 and result.havedata:
        return 'Hello from AWS Lambda using Python' + sys.version + '!' + str(result.data.address_list)
```

2. Create new Dockerfile or replace current one with the following content. Basically it is mostly the same code but copying and running `lambda_function.py` file:

```dockerfile
FROM public.ecr.aws/lambda/python:3.12
RUN dnf install openssl-devel expat-devel wget make automake gcc gcc-c++ kernel-devel swig tar gzip -y
COPY requirements.txt ${LAMBDA_TASK_ROOT}
RUN wget https://nlnetlabs.nl/downloads/unbound/unbound-latest.tar.gz
RUN tar xzf unbound-latest.tar.gz
RUN cd unbound-1.21.1 &&  ./configure --with-pyunbound --with-pythonmodule \
&& make && make install
RUN pip install -r requirements.txt
COPY lambda_function.py ${LAMBDA_TASK_ROOT}
RUN rm -rf unbound-1.22.0
CMD [ "lambda_function.handler" ]
```

3. Follow steps from the [Running unbound and open-mpic inside AWS lambda container](#running-unbound-and-open-mpic-inside-aws-lambda-container).
