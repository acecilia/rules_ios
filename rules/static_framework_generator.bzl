"""This file contains rules to build framework binaries from your podfile or cartfile"""

load("@build_bazel_rules_apple//apple:providers.bzl", "AppleResourceInfo")

################
# Aspect
################

def _get_resource_targets(deps):
    return depset(transitive = _get_attr_values_for_name(deps, _TargetInfo, "owned_resource_targets"))

_TargetInfo = provider()

def _get_attr_values_for_name(deps, provider, field):
    return [
        getattr(dep[provider], field)
        for dep in deps
        if dep and provider in dep
    ]

def _collect_resources_aspect_impl(target, ctx):
    resource_targets = []
    if ctx.rule.kind == "alias":
        actual = getattr(ctx.rule.attr, "actual")
        if actual and _TargetInfo in actual:
            resource_targets += actual[_TargetInfo].resource_targets
    elif _is_resources_target(ctx):
        resource_targets.append(target)

    provider = _make_provider(ctx, resource_targets)
    return [provider]

def _is_top_level_target(ctx):
    return ctx.rule.kind == "apple_framework_packaging"

def _is_resources_target(ctx):
    return ctx.rule.kind == "_precompiled_apple_resource_bundle"

def _make_provider(ctx, resource_targets):
    deps = getattr(ctx.rule.attr, "deps", [])
    transitive_resource_targets = depset(
        resource_targets,
        transitive = _get_attr_values_for_name(deps, _TargetInfo, "transitive_resource_targets"),
    )

    return _TargetInfo(
        transitive_resource_targets = depset([]) if _is_top_level_target(ctx) else transitive_resource_targets,
        owned_resource_targets = transitive_resource_targets if _is_top_level_target(ctx) else depset([]),
    )

_collect_resources_aspect = aspect(
    implementation = _collect_resources_aspect_impl,
    attr_aspects = ["deps", "actual"],
)

################
# Rule
################

def _get_resource_bundles(ctx, target):
    resource_bundles = []
    for resource_target in _get_resource_targets([target]).to_list():
        if AppleResourceInfo in resource_target:
            for resource_group in resource_target[AppleResourceInfo].unprocessed:
                resource_files = resource_group[2].to_list()
                if len(resource_files) == 0:
                    continue

                paths_to_copy = " ".join([file.path for file in resource_files])
                bundle = struct(
                    name = resource_group[0],
                    files = resource_files,
                )
                resource_bundles.append(bundle)
    return resource_bundles

def _get_existing_framework_path(target):
    existing_framework_files = target.files.to_list()
    if existing_framework_files:
        framework_path = existing_framework_files[0].dirname
        if framework_path.endswith(".framework"):
            return framework_path

    fail("The target %s does not produce any framework" % target.label.name)

def _get_existing_framework_name(target):
    return _get_existing_framework_path(target).split("/")[-1].replace(".framework", "")

def _declare_framework(ctx, target):
    framework_name = _get_existing_framework_name(target)
    return ctx.actions.declare_directory(framework_name + ".framework")

def _make_bundles_args(framework_destination, resource_bundles):
    files = []
    for resource_bundle in resource_bundles:
        # Put in a list all the resource files, adding the destination bundle at the end, so the full list
        # can be passed as arguments to ditto (ditto expects the destination to be the last argument)
        file_list = [file.path for file in resource_bundle.files] + [framework_destination + "/Resources/" + resource_bundle.name]

        # Make the list a comma-separated string, so it can be passed to the bash script
        files.append(",".join(file_list))
    return files

def _make_frameworks(ctx):
    frameworks = []
    for target in ctx.attr.targets:
        # Preparation
        framework = _declare_framework(ctx, target)
        resource_bundles = _get_resource_bundles(ctx, target)

        # Inputs
        framework_inputs = target.files.to_list()
        resource_bundle_inputs = [file for bundle in resource_bundles for file in bundle.files]

        # Arguments
        framework_origin_arg = _get_existing_framework_path(target)
        framework_destination_arg = framework.path
        bundle_files_destination_arg = " ".join(_make_bundles_args(framework_destination_arg, resource_bundles))

        ctx.actions.run_shell(
            outputs = [framework],
            inputs = framework_inputs + resource_bundle_inputs,
            command = '''\
rsync -a "$1/" "$2"
for bundle_files in $3; do
    bundle_files_args=$(echo "$bundle_files" | tr "," " ")
    ditto $bundle_files_args
done''',
            arguments = [framework_origin_arg, framework_destination_arg, bundle_files_destination_arg],
        )
        frameworks.append(framework)
    return frameworks

def _static_framework_generator_impl(ctx):
    frameworks = _make_frameworks(ctx)
    return [DefaultInfo(files = depset(frameworks))]

# Making below rule public in order to properly generate its documentation until the
# https://github.com/bazelbuild/stardoc/issues/27 issue is resolved
static_framework_generator = rule(
    implementation = _static_framework_generator_impl,
    doc = """\
This rule packs a framework together with its resource bundles
""",
    attrs = {
        "targets": attr.label_list(
            mandatory = True,
            aspects = [_collect_resources_aspect],
            doc = "The list of targets to use for packing the frameworks",
        ),
    },
)
