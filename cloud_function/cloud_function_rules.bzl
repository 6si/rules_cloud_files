def contains(pattern):
    return "contains:" + pattern

def startswith(pattern):
    return "startswith:" + pattern

def endswith(pattern):
    return "endswith:" + pattern

def _is_ignored(path, patterns):
    for p in patterns:
        if p.startswith("contains:"):
            if p[len("contains:"):] in path:
                return True
        elif p.startswith("startswith:"):
            if path.startswith(p[len("startswith:"):]):
                return True
        elif p.startswith("endswith:"):
            if path.endswith(p[len("endswith:"):]):
                return True
        else:
            fail("Invalid pattern: " + p)

    return False

def _short_path(file_):
    # Remove prefixes for external and generated files.
    # E.g.,
    #   ../py_deps_pypi__pydantic/pydantic/__init__.py -> pydantic/__init__.py
    short_path = file_.short_path
    if short_path.startswith("../"):
        second_slash = short_path.index("/", 3)
        short_path = short_path[second_slash + 1:]

    # Theres gotta be a better way to do this
    if short_path.startswith("site-packages"):
        short_path = short_path.replace("site-packages/","")
    if short_path.startswith("services/lambda/layers"):
        short_path = "/".join(short_path.split("/")[4:])
    if short_path.startswith("services/lambda/functions"):
        short_path = "/".join(short_path.split("/")[5:])
    if short_path.startswith("python_v2/"):
        short_path = "/".join(short_path.split("/")[2:])
    return short_path


def _py_lambda_zip_impl(ctx):
    deps = ctx.attr.target[DefaultInfo].default_runfiles.files

    f = ctx.outputs.output

    args = []
    for dep in deps.to_list():
        short_path = _short_path(dep)

        # Skip ignored patterns
        if _is_ignored(short_path, ctx.attr.ignore):
            continue

        args.append(short_path + "=" + dep.path)

    ctx.actions.run(
        outputs = [f],
        inputs = deps,
        executable = ctx.executable._zipper,
        arguments = ["cC", f.path] + args,
        progress_message = "Creating archive...",
        mnemonic = "archiver",
    )

    out = depset(direct = [f])
    return [
        DefaultInfo(
            files = out,
        ),
        OutputGroupInfo(
            all_files = out,
        ),
    ]

_py_lambda_zip = rule(
    implementation = _py_lambda_zip_impl,
    attrs = {
        "target": attr.label(),
        "ignore": attr.string_list(),
        "_zipper": attr.label(
            default = Label("@bazel_tools//tools/zip:zipper"),
            cfg = "host",
            executable = True,
        ),
        "output": attr.output(),
    },
    executable = False,
    test = False,
)

def py_lambda_zip(name, target, ignore, **kwargs):
    _py_lambda_zip(
        name = name,
        target = target,
        ignore = ignore,
        output = name + ".zip",
        **kwargs
    )

# Just a wrapper of gen rule:
# genrule(
#     name = "upload_to_s3",
#     srcs = [":lambda_archive"],
#     outs = ["upload_to_s3_done"],
#     cmd = """
#         CURRENT_DATE=`date '+%Y/%m/%d'`
#         FILE_NAME=`cd services/ && git rev-parse HEAD`.zip
#         aws --profile prod-engineering-labs s3 cp $(location :lambda_archive) s3://6si-dheeraj-test-tmp/$$CURRENT_DATE/$$FILE_NAME &&
#         touch $@
#     """,
# )

def _upload_to_s3_impl(ctx):
    output = ctx.actions.declare_file(ctx.attr.name + "_done")

    profile_option = ""
    if ctx.attr.profile != "":
        profile_option = "--profile " + ctx.attr.profile

    key_prefix_option = ""
    if ctx.attr.key_prefix != "":
        key_prefix_option = ctx.attr.key_prefix + "/"

    cmd = """
        set -e
        CURRENT_DATE=`date '+%Y/%m/%d'`
        FILE_NAME=`cd services/ && git rev-parse HEAD`.zip
        KEY={key_prefix}{function_name}/$CURRENT_DATE/$FILE_NAME
        aws {profile_option} s3 cp {src} s3://{bucket}/$KEY
        echo S3_SOURCE > {out}
        echo $KEY >> {out}
        echo {function_name} >> {out}
        echo {bucket} >> {out}
    """.format(
        src=ctx.file.src.path, 
        out=output.path, 
        function_name=ctx.attr.function_name,
        profile_option=profile_option, 
        bucket=ctx.attr.bucket,
        key_prefix=key_prefix_option,
    )

    ctx.actions.run_shell(
        outputs=[output],
        inputs=[ctx.file.src],
        command=cmd,
    )

    return DefaultInfo(files=depset([output]))


lambda_upload_s3 = rule(
    implementation=_upload_to_s3_impl,
    attrs={
        "src": attr.label(allow_single_file=True),
        # function_name MUST MATCH the name of the lambda function within AWS
        "function_name": attr.string(),
        # AWS config profile to use
        "profile": attr.string(default=""),
        # S3 Bucket
        "bucket": attr.string(default="6si-lambda"),
        # S3 key Prefix, useful for testing
        "key_prefix": attr.string(default=""),
    },
    outputs={"done": "%{name}_done"},
)


def _lambda_deploy_code_imp(ctx):
    output = ctx.actions.declare_file(ctx.attr.name + "_done")

    profile_option = ""
    if ctx.attr.profile != "":
        profile_option = "--profile " + ctx.attr.profile

    cmd = """
        set -e
        mapfile -t lines < {src}

        # Confirm the correct target is used
        SOURCE=${{lines[0]}}
        if [[ "$SOURCE" != "S3_SOURCE" ]]; then
            echo "Assertion failed: expected var to be 'S3_SOURCE' , but got '$SOURCE'"
            exit 1
        fi

        KEY=${{lines[1]}}
        FUNCTION_NAME=${{lines[2]}}
        BUCKET=${{lines[3]}}
        echo FUNCTION_NAME: $FUNCTION_NAME, BUCKET: $BUCKET, KET: $KEY
        aws lambda {profile_option} update-function-code --function-name $FUNCTION_NAME --s3-bucket $BUCKET --s3-key $KEY
        echo $KEY > {out}
    """.format(
        src=ctx.file.src.path, 
        out=output.path, 
        profile_option=profile_option, 
    )

    ctx.actions.run_shell(
        outputs=[output],
        inputs=[ctx.file.src],
        command=cmd,
    )

    return DefaultInfo(files=depset([output]))

lambda_deploy = rule(
    implementation=_lambda_deploy_code_imp,
    attrs={
        # Must be a label to a lambda_uplaod_s3 rule
        "src": attr.label(allow_single_file=True),
        # AWS config profile to use
        "profile": attr.string(default=""),
    },
    outputs={"done": "%{name}_done"},
)