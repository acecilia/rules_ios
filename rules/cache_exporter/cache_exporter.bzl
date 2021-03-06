def cache_exporter(**kwargs):
    _cache_exporter_test(
        tags = ["no-sandbox"],
        **kwargs
    )

def _make_files_list(ctx):
    return [file for target in ctx.attr.targets for file in target.files.to_list()]

def _make_destination(ctx):
    if ctx.attr.destination_relative_to_package:
        return ctx.label.package + "/" + ctx.attr.destination_relative_to_package
    else:
        return ctx.attr.destination_relative_to_workspace

def _make_installer(ctx, files, destination):
    installer = ctx.actions.declare_file("installer.sh")
    ctx.actions.expand_template(
        template = ctx.file._installer_template,
        output = installer,
        substitutions = {
            "$(files)": " ".join(files),
            "$(destination)": destination,
        },
        is_executable = True,
    )
    return installer

def _cache_exporter_impl(ctx):
    files = _make_files_list(ctx)
    destination = _make_destination(ctx)
    installer = _make_installer(ctx, [file.path for file in files], destination)
    return [
        DefaultInfo(
            executable = installer,
            runfiles = ctx.runfiles(files = files),
        ),
    ]

_cache_exporter_test = rule(
    implementation = _cache_exporter_impl,
    doc = """\
Export the outputs of the targets to a destination outside the bazel cache

Moving artifacts produced by Bazel to a location out of the cache can be useful for
compatibility with other build systems.

For example, it would be possible to integrate with cocoapods as follows:
1- Build targets with Bazel
2- Use this rule to export the built frameworks outside of the cache
3- Generate podspec files containing the generated frameworks as vendored_frameworks, so they can be 
   integrated in a cocoapods setup, substituting their source code counterparts (useful to cut build time)
""",
    attrs = {
        "targets": attr.label_list(
            mandatory = True,
            doc = "The list of targets which outputs should be exported",
        ),
        "destination_relative_to_workspace": attr.string(
            mandatory = False,
            default = "static_framework_generator",
            doc = "Destination of the exported files, relative to the workspace",
        ),
        "destination_relative_to_package": attr.string(
            mandatory = False,
            doc = "Destination of the exported files, relative to the package",
        ),
        "_installer_template": attr.label(
            default = Label("//rules/cache_exporter:installer.sh"),
            allow_single_file = ["sh"],
        ),
    },
    # Ideally this rule would not be a test: it would be an executable to be run with `bazel run`.
    # The problem with `bazel run` is that you can only execute one target per `bazel run` invocation.
    # See: https://github.com/bazelbuild/bazel/issues/10855
    #
    # A workaround is to mark this rule as a test, because `bazel test` allows to execute multiple
    # test targets in paralel. Running `bazel test` once with multiple targets is much faster than
    # running `bazel run` with one target multiple times
    test = True,
)
