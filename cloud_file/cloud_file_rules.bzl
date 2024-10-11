"""
Module for downloading and validating the checksum of the downloaded file.

This module contains the `validate_checksum` function and `cloud_file_download` function
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

_CLOUD_FILE_DOWNLOAD = """
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "file",
    srcs = ["{}"],
)
"""

def cloud_file_download(
        repo_ctx,
        file_path,
        expected_sha256,
        provider,
        bucket = "",
        build_file = "",
        rename_file = "",
        profile = ""):
    """
    Securely download the file from the cloud provider.

    The function downloads the specified file from a cloud provider and checks its
    sha256 hash to verify its integrity.

    Args:
        repo_ctx (object): Bazel repository context.
        file_path (str): Path to the file to download from Cloud Provider.
        expected_sha256 (str): Expected sha256 hash of the downloaded file.
        provider (str): Name of the cloud provider, default is set to "s3".
        bucket (str): Name of the bucket containing the file.
        build_file(str): Build file for the downloaded file
        rename_file(str): Name of the file to rename it to
        profile (str): CLI profile to use for authentication.

    Raises:
        Exception: If the command line utility is not found, if downloading the
        file fails or if the sha256 hash of the downloaded file does not match the
        expected value.
    """
    filename = repo_ctx.path(file_path).basename
    if provider == "s3":
        tool_path = repo_ctx.which("aws")
        if tool_path == None:
            fail("Could not find command line utility for S3")
        extra_flags = ["--profile", profile] if profile else []
        src_url = "s3://{}/{}".format(bucket, file_path)
        if rename_file:
            cmd = [tool_path] + extra_flags + ["s3", "cp", src_url, "./" + rename_file]
        else:
            cmd = [tool_path] + extra_flags + ["s3", "cp", src_url, "."]
    elif provider == "gcp":
        tool_path = repo_ctx.which("gsutil")
        if tool_path == None:
            fail("Could not find command line utility for GCP")
        src_url = "gs://{}/{}".format(bucket, file_path)
        cmd = [tool_path, "cp", src_url, "."]
    else:
        fail("Provider not supported: " + provider.capitalize())

    # Download.
    repo_ctx.report_progress("Downloading {}.".format(src_url))
    result = repo_ctx.execute(cmd, timeout = 1800)
    if result.return_code != 0:
        fail("Failed to download {} from {}: {}".format(src_url, provider.capitalize(), result.stderr))

    # Verify
    if rename_file:
        filename = rename_file
    else:
        filename = repo_ctx.path(src_url).basename
    validate_checksum(repo_ctx, file_path, filename, expected_sha256)
    
    # Default build file set to get the file
    repo_ctx.file("BUILD.bazel", _CLOUD_FILE_DOWNLOAD.format(filename), executable = False)
    
    # Use user provided build file if exists
    bash_path = repo_ctx.os.environ.get("BAZEL_SH", "bash")
    if build_file:
        repo_ctx.execute([bash_path, "-c", "rm -f BUILD BUILD.bazel"])
        repo_ctx.symlink(build_file, "BUILD.bazel")

def _cloud_file_impl(ctx):
    cloud_file_download(
        ctx,
        ctx.attr.file_path,
        ctx.attr.sha256,
        provider = ctx.attr._provider,
        build_file = ctx.attr.build_file,
        rename_file = ctx.attr.rename_file,
        profile = ctx.attr.profile if hasattr(ctx.attr, "profile") else "",
        bucket = ctx.attr.bucket if hasattr(ctx.attr, "bucket") else "",
    )

s3_file = repository_rule(
    implementation = _cloud_file_impl,
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
        "rename_file": attr.string(
            mandatory = False,
            doc = "Name of the file to want to rename it to",
        ),
        "_provider": attr.string(default = "s3"),
    },
)

gcp_file = repository_rule(
    implementation = _cloud_file_impl,
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
        "_provider": attr.string(default = "gcp"),
    },
)
