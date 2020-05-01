import UIKit
import InputMask

/* Declaring extension Foo makes the framework build fail with the error:
 * ./bazel-out/apl-ios_x86_64-fastbuild/bin/tests/mixed-source-import-swift/ios/MixedSourceFramework-Swift.h:184:9: fatal error: module 'SwiftLibrary' not found
 * @import SwiftLibrary;
 * ~~~~~~~^~~~~~~~~~~~
 * 1 error generated.
 *
 * Commenting out extension Foo: the framework builds without any problem
 */
extension MaskedTextInputListener { }
