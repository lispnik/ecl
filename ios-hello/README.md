# ECL Hello — Common Lisp on the iPhone

A one-screen iOS app that boots the ECL image built by `../build.sh` and
evaluates forms in it. The transcript shows the running implementation; the
field at the bottom is a small REPL.

## Building

    cd ..
    ./build.sh          # produces ../ecl-iOS and ../ecl-iOS-sim
    cd ios-hello
    ./run-sim.sh        # run in the iOS Simulator
    ./install.sh        # build, sign, install on a connected iPhone

Or open `ECLHello.xcodeproj` in Xcode, pick a destination, and press Run.

## Simulator

    ./run-sim.sh                 # first available iPhone simulator
    ./run-sim.sh "iPhone 17"     # by name

The simulator needs no code signing, no developer account and no Developer
Mode, so this is the quick way to check a change. It links against
`../ecl-iOS-sim`, a second cross build: simulator objects carry the
`IOSSIMULATOR` Mach-O platform and will not link into a device build, or the
other way round. The Xcode project picks the right one per destination through
`LIBRARY_SEARCH_PATHS[sdk=...]`.

## Device

### First-time device setup

The phone needs two things, both done on the phone itself:

* **Developer Mode on** — Settings › Privacy & Security › Developer Mode,
  then restart. The toggle only appears after a Mac has tried to use the
  device for development at least once.
* **Unlocked** while it is plugged in, and set to trust this Mac.

### Signing

The project is set to team `Q47YS469F2` with automatic signing. If Xcode
rejects the bundle identifier as taken, change `PRODUCT_BUNDLE_IDENTIFIER`
(currently `org.ecl.ECLHello`) to anything unique.

## How it hangs together

`ECLRuntime.m` is the whole of the ECL-facing side, and it is short:

* `cl_boot` starts the image. Everything Lisp lives inside `libecl.a` — there
  are no `.fas` files to ship and nothing to find at runtime.
* ECL's signal traps are switched off. It normally catches `SIGSEGV` and
  friends to turn them into Lisp conditions, which on iOS fights with the
  system and the debugger.
* `HOME` is pointed at the app's Documents directory, the only place the
  process may write.
* `(ext:install-bytecodes-compiler)` is essential: there is no C compiler on
  the phone, so `compile` has to produce bytecodes. Without it anything that
  compiles a function fails, including parts of CLOS.
* Strings cross the boundary as UTF-32 in both directions, so evaluating
  `(code-char 233)` gives you `é` rather than mojibake.

## Building UIKit from Lisp

`ECLHello/lisp/gui.lisp` is loaded from the bundle at boot and constructs a
real `UIStackView` of `UILabel`s inside the canvas view -- interpreted, with
no C compiler anywhere. Press **Lisp GUI**.

It reaches UIKit through the Objective-C runtime using ECL's dynamic FFI
(`:dffi` is in `*features*`, libffi is linked). Three points worth knowing:

* `ffi:c-inline`, which most ECL FFI examples use, is useless here -- it emits
  C and needs a compiler. `si:call-cfun` builds the call frame at runtime and
  does not.
* `si:find-foreign-symbol` also fails, with *"does not work when ECL is
  statically linked"*. The guard is `ENABLE_DLOPEN`, which `--disable-shared`
  turns off. Only symbol *lookup* is lost, so the app hands Lisp the addresses
  of `objc_getClass`, `sel_registerName` and `objc_msgSend` instead
  (`+[ECLRuntime installObjCBridge]`) and everything else works.
* `objc_msgSend` is variadic, but Apple's arm64 ABI puts variadic arguments on
  the stack and fixed ones in registers, so Apple's own guidance is to cast it
  to the exact prototype per call site. Giving libffi a non-variadic signature
  each time is exactly that.

Auto Layout is used rather than frames on purpose: anchors are objects and
constants are `CGFloat`, so nothing has to pass a `CGRect` by value, which
ECL's FFI cannot express.

The one thing that does not work is the other direction. A callback from UIKit
into Lisp needs an `ffi:defcallback`, hence a libffi closure, hence
writable-then-executable memory -- which iOS forbids. That is why the buttons
are wired in Objective-C and merely carry a Lisp form as their payload.

## Limits

Interpreted and bytecode-compiled code only. `compile-file` to native code
needs a C toolchain, which iOS does not have and does not permit.

The four static libraries (`-lecl -leclgc -leclgmp -leclffi`) add about 3.4 MB
to the binary.
