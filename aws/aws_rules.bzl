def validate_checksum(repo_ctx, url, local_path, expected_sha256):
    # Verify checksum
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

def s3_file_download(
        repo_ctx,
        file_path,
        expected_sha256,
        provider,
        patches,
        patch_args,
        bucket = "",
        build_file = "",
        build_file_contents = "",
        profile = ""):
    """ Securely downloads AWS S3 files """
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
    
    # If patches are provided, apply them.
    if patches != None and len(patches) > 0:
        patches = [str(repo_ctx.path(patch)) for patch in patches]

        # Built in Bazel patch only supports -pN or no parameters at all, so we
        # determine if we can use the built in patch.
        only_strip_param = (patch_args != None and
                            len(patch_args) == 1 and
                            patch_args[0].startswith("-p") and
                            patch_args[0][2:].isdigit())
        strip_n = 0
        if only_strip_param:
            strip_n = int(patch_args[0][2:])

        if patch_args == None or only_strip_param:
            # OK to use built-in patch.
            for patch in patches:
                repo_ctx.patch(patch, strip = strip_n)
        else:
            # Must use extrenal patch. Note that this hasn't been tested, so it
            # might not work. If it's busted, please send a PR.
            patch_path = repo_ctx.which("patch")
            for patch in patches:
                patch_cmd = [patch_path] + patch_args + ["-i", patch]
                result = repo_ctx.execute(patch_cmd)
                if result.return_code != 0:
                    fail("Patch {} failed to apply.".format(patch))

def _s3_file_impl(ctx):
    s3_file_download(
        ctx,
        ctx.attr.file_path,
        ctx.attr.sha256,
        provider = ctx.attr._provider,
        patches = ctx.attr.patches,
        patch_args = ctx.attr.patch_args,
        build_file = ctx.attr.build_file,
        build_file_contents = ctx.attr.build_file_contents,
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
            doc = "BUILD file for the unpacked archive",
        ),
        "build_file_contents": attr.string(doc = "The contents of the build file for the target"),
        "patches": attr.label_list(doc = "Patches to apply, if any.", allow_files = True),
        "patch_args": attr.string_list(doc = "Arguments to use when applying patches."),
        "_provider": attr.string(default = "s3"),
    },
)
