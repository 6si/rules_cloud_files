"""
Module for downloading and validating the checksum of the downloaded file.

This module contains the `validate_checksum` function and `s3_file_download` function
"""
def validate_checksum(repo_ctx, url, local_path, expected_sha256):
    """
    Verify the checksum of the downloaded file.

    This function uses the sha256sum command to generate the checksum of the
    file located at local_path. The generated checksum is compared to the
    expected_sha256 value and if they do not match, the function raises an error.

    Args:
        repo_ctx (object): The repository context object.
        url (str): The URL of the file.
        local_path (str): The local path of the file on the system.
        expected_sha256 (str): The expected sha256 value of the file.

    Raises:
    Exception: If the checksum of the file does not match the expected_sha256 value.
    """
    sha256_path = repo_ctx.which("sha256sum")
    repo_ctx.report_progress("Checksumming {}.".format(local_path))
    sha256_result = repo_ctx.execute([sha256_path, local_path])
    if sha256_result.return_code != 0:
        fail("Failed to verify checksum: {}".format(sha256_result.stderr))
    sha256 = sha256_result.stdout.split(" ")[0]
    if sha256 != expected_sha256:
        fail("Checksum mismatch for {}, expected {}, got {}.".format(
            url,
            expected_sha256,
            sha256,
        ))

_S3_FILE_DOWNLOAD = """
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "file",
    srcs = ["{}"],
)
"""

def s3_file_download(
        repo_ctx,
        file_path,
        expected_sha256,
        provider,
        bucket = "",
        build_file = "",
        profile = ""):
    """Securely download an AWS S3 file and apply patches if necessary.

    The function downloads the specified file from an AWS S3 bucket and checks its
    sha256 hash to verify its integrity. If patches are provided, it will apply them
    to the downloaded file.

    Args:
        repo_ctx (object): Bazel repository context.
        file_path (str): Path to the file to download from S3.
        expected_sha256 (str): Expected sha256 hash of the downloaded file.
        provider (str): Name of the cloud provider, in this case "AWS".
        bucket (str): Name of the AWS S3 bucket containing the file.
        build_file(str): Build file for the downloaded file
        profile (str): AWS CLI profile to use for authentication.

    Raises:
    Exception: If the aws command line utility is not found, if downloading the
    file fails, if the sha256 hash of the downloaded file does not match the
    expected value, or if applying a patch fails.
"""
    filename = repo_ctx.path(file_path).basename

    tool_path = repo_ctx.which("aws")
    extra_flags = ["--profile", profile] if profile else []
    src_url = "s3://{}/{}".format(bucket, file_path)
    cmd = [tool_path] + extra_flags + ["s3", "cp", src_url, "."]
    if tool_path == None:
        fail("Could not find command line utility for {}".format(provider.capitalize()))

    # Download.
    repo_ctx.report_progress("Downloading {}.".format(src_url))
    result = repo_ctx.execute(cmd, timeout = 1800)
    if result.return_code != 0:
        fail("Failed to download {} from {}: {}".format(src_url, provider.capitalize(), result.stderr))

    # Verify.
    filename = repo_ctx.path(src_url).basename
    validate_checksum(repo_ctx, file_path, filename, expected_sha256)
    
    # Default build file set to get the file
    repo_ctx.file("BUILD.bazel", _S3_FILE_DOWNLOAD.format(filename), executable = False)
    
    # Use user provided build file if exists
    bash_path = repo_ctx.os.environ.get("BAZEL_SH", "bash")
    if build_file:
        repo_ctx.execute([bash_path, "-c", "rm -f BUILD BUILD.bazel"])
        repo_ctx.symlink(build_file, "BUILD.bazel")

def _s3_file_impl(ctx):
    s3_file_download(
        ctx,
        ctx.attr.file_path,
        ctx.attr.sha256,
        provider = ctx.attr._provider,
        build_file = ctx.attr.build_file,
        profile = ctx.attr.profile if hasattr(ctx.attr, "profile") else "",
        bucket = ctx.attr.bucket if hasattr(ctx.attr, "bucket") else "",
    )

s3_file = repository_rule(
    implementation = _s3_file_impl,
    attrs = {
        "bucket": attr.string(mandatory = True, doc = "Bucket name"),
        "file_path": attr.string(
            mandatory = True,
            doc = "Relative path to the archive file within the bucket",
        ),
        "profile": attr.string(doc = "Profile to use for authentication."),
        "sha256": attr.string(mandatory = True, doc = "SHA256 checksum of the archive"),
        "build_file": attr.label(
            allow_single_file = True,
            doc = "BUILD file for the downloaded file",
        ),
        "_provider": attr.string(default = "s3"),
    },
)
