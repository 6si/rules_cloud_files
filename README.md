# Rules Cloud Files

This repo contains Bazel rules related to managing cloud resources
- fetching files from a cloud storage provider, namely, AWS S3, etc.
- uploading lambda code to s3 and deploying new code to lambda

## Set up
To use any of the rules, add the following to your WORSKAPCE file
```starlark
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")
git_repository(
    name = "rules_cloud_files",
    remote = "https://github.com/6si/rules_cloud_files.git",
    commit = "d8097550e5c507f29c760a670daa3230c52dda59",
)

```

## Usage Cloud Storage
- Example 
```starlark
load("@rules_cloud_files//cloud_file:cloud_file_rules.bzl", "s3_file")

s3_file(
    name = "my_file",
    bucket = "my-bucket",
    file_path = "my-file.tgz",
    sha256 = "74a0bdd648f009ebce72494f54903230a9dcebaca1d438a13c1c691ad2f1e110",
)
```
This is an example to download the file s3://my-bucket/my-file.tgz.

## Usage Cloud Functions
Currently only AWS lambda functions are supported. For Lambda functions there are 3 rules for your use
- Import the functions into your BUILD file
```starlark 
load("@rules_cloud_files//cloud_function:cloud_function_rules.bzl", "py_lambda_zip", "lambda_upload_s3", "lambda_deploy")
```

- py_lambda_zip: packages your py library into a zip that is compliant with AWS lambda's expected structuer
- Here is an example on how to structure your lambda code: https://github.com/6si/ntropy/blob/1a5922f3f905d3dd962f9f14a8bc0847fb12b883/services/lambda/functions/logging_pigtailv3_transformer/BUILD#L9
```starlark
py_lambda_zip(
    name = "lambda_archive",
    ignore = [],
    target = ":py_lib",
)
```

- lambda_upload_s3: Will upload your lambda code to s3. Using this is important as it it creates the proper key structure to 
ensure that there are no colisions and that your uploaded code can be used by the lambda. Check the code for details behind 
each of the arguments
```starlark
lambda_upload_s3(
    name = "upload_test",
    src = ":lambda_archive",
    profile = "prod-engineering-labs",
    function_name = "dev_logging_pigtail_jobs_transformer",
    bucket = "6si-lambda-dev",
    key_prefix = "labs",
)
```

- lambda_deploy: Will deploy the code you uploaded to s3, The src to this MUST BE a label to lambd_upload_s3
```starlark
lambda_deploy(
    name = "deploy_dev",
    src = "upload_dev",
)

```