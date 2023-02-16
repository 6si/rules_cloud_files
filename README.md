# Rules Cloud Files

This repo contains Bazel rules related to fetching files from a cloud storage provider, namely, AWS S3, etc.

## Usage
- Example 
```starlark
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")
git_repository(
    name = "rules_cloud_files",
    remote = "https://github.com/6si/rules_cloud_files.git",
    commit = "d8097550e5c507f29c760a670daa3230c52dda59",
)

load("@rules_cloud_files//cloud_file:cloud_file_rules.bzl", "cloud_file")

cloud_file(
    name = "my_file",
    bucket = "bootstrap-software",
    file_path = "hadoop2-configs-20180306012540.tgz",
    sha256 = "74a0bdd648f009ebce72494f54903230a9dcebaca1d438a13c1c691ad2f1e110",
)
```
This is an example to download the file from s3://bootstrap-software/hadoop2-configs-20180306012540.tgz.
