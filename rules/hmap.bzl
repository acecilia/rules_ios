load("@build_bazel_rules_swift//swift:swift.bzl", "SwiftInfo")

def _make_headermap_impl(ctx):
    """Implementation of the headermap() rule. It creates a text file with
    the mappings and creates an action that calls out to the hmapbuild
    tool included here to create the actual .hmap file.

    :param ctx: context for this rule. See
           https://docs.bazel.build/versions/master/skylark/lib/ctx.html

    :return: provider with the info for this rule

    """

    # Write a file for *this* headermap, this is a temporary file
    input_f = ctx.actions.declare_file(ctx.label.name + "_input.txt")
    all_hdrs = list(ctx.files.hdrs)
    for provider in ctx.attr.direct_hdr_providers:
        if apple_common.Objc in provider:
            all_hdrs += provider[apple_common.Objc].direct_headers
        elif CcInfo in provider:
            all_hdrs += provider[CcInfo].compilation_context.direct_headers
        else:
            fail("direct_hdr_provider %s must contain either 'CcInfo' or 'objc' provider" % provider)

    ctx.actions.write(
        content = "\n".join([h.path for h in all_hdrs]),
        output = input_f,
    )

    # Add a list of headermaps in text or hmap format
    merge_hmaps = {}
    inputs = [input_f]
    args = []
    if ctx.attr.namespace_headers:
        args += ["--namespace", ctx.attr.namespace]

    if merge_hmaps:
        paths = []
        for hdr in merge_hmaps.keys():
            inputs.append(hdr)
            paths.append(hdr.path)
        merge_hmaps_file = ctx.actions.declare_file(ctx.label.name + ".merge_hmaps")
        inputs.append(merge_hmaps_file)
        ctx.actions.write(
            content = "\n".join(paths) + "\n",
            output = merge_hmaps_file,
        )
        args += ["--merge-hmaps", merge_hmaps_file.path]

    args += [input_f.path, ctx.outputs.headermap.path]
    ctx.actions.run(
        inputs = inputs,
        mnemonic = "HmapCreate",
        arguments = args,
        executable = ctx.executable._headermap_builder,
        outputs = [ctx.outputs.headermap],
    )
    objc_provider = apple_common.new_objc_provider(
        header = depset([ctx.outputs.headermap]),
    )
    return struct(
        files = depset([ctx.outputs.headermap]),
        providers = [objc_provider],
        objc = objc_provider,
        headers = depset([ctx.outputs.headermap]),
    )

# Derive a headermap from transitive headermaps
# hdrs: a file group containing headers for this rule
# namespace: the Apple style namespace these header should be under
headermap = rule(
    implementation = _make_headermap_impl,
    output_to_genfiles = True,
    attrs = {
        "namespace": attr.string(
            mandatory = True,
            doc = "The prefix to be used for header imports when namespace_headers is true",
        ),
        "hdrs": attr.label_list(
            mandatory = True,
            allow_files = True,
            doc = "The list of headers included in the headermap",
        ),
        "direct_hdr_providers": attr.label_list(
            mandatory = False,
            doc = "Targets whose direct headers should be added to the list of hdrs",
        ),
        "namespace_headers": attr.bool(
            mandatory = True,
            doc = "Whether headers should be importable with the namespace as a prefix",
        ),
        "_headermap_builder": attr.label(
            executable = True,
            cfg = "host",
            default = Label(
                "//rules/hmap:hmaptool",
            ),
        ),
    },
    outputs = {"headermap": "%{name}.hmap"},
    doc = """\
Creates a binary headermap file from the given headers,
suitable for passing to clang.

This can be used to allow headers to be imported at a consistent path,
regardless of the package structure being used.
    """,
)
