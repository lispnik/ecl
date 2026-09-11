# This is a fork

This is lispnik/ecl, a fork of ECL. Upstream is
https://gitlab.com/embeddable-common-lisp/ecl, and everything below this
section is its README, unchanged.

`develop` here is upstream's `develop` plus a small number of fixes that
are not upstream yet. Each fix is also kept on its own branch, rebased on
upstream's `develop`, so that what it changes can be read on its own:
`git diff develop..<branch>` on a fresh clone of upstream is the whole of
it. The fixes exist so that Objective-C can be driven from ECL on macOS
and iOS -- see https://github.com/lispnik/objc and
https://github.com/lispnik/asdf-ios-app, which build this fork's `develop`
-- and none of them is specific to that use.

## What differs from upstream

`fix-dlsym-default-darwin` -- src/c/ffi/libraries.d

  The `:default` module resolved symbols with `dlsym(0, name)`. On Darwin
  a null handle is not the global scope -- `RTLD_DEFAULT` is `(void *)-2`
  -- so `:default` resolved nothing, not even `strlen`, and CFFI's ECL
  backend, which looks foreign functions up by name, could not work on
  macOS at all. It uses `RTLD_DEFAULT` where that is defined.

`ffi-closure-alloc-check` -- src/c/ffi.d, and tests

  `si:make-dynamic-callback` handed out a libffi closure's writable record
  as the callback, rather than the entry point libffi returns beside it.
  The two coincide only on platforms where memory may be both writable
  and executable; on iOS and arm64 macOS libffi maps them apart, and
  calling the record jumped into the heap. It returns the entry point
  now. Found on the way: a failed closure allocation was a null-pointer
  crash and is an error; a callback arriving on a thread ECL did not
  create died in `ecl_process_env()` and now imports the thread, which
  is what makes a closure usable from a libdispatch worker; and the
  closure record was not kept reachable by the collector, so the first
  collection freed it under a live trampoline. The one existing test of
  a dynamic callback, ffi.0003, had been disabled with `#+(and (or) ...)`;
  it runs again, with two more beside it.

`dffi-aggregates` -- src/c/ffi.d, src/lsp/ffi.lsp, the manual, and tests

  The dynamic FFI passes and returns structures by value.
  `si:call-cfun`, `ffi:def-function` and `ffi:defcallback` take
  `(:struct ...)` designators, with nested structures and array members,
  and libffi supplies the layout and the calling convention. Before this
  a structure could only be smuggled through as the scalars it is made
  of, which on AArch64 is right for a homogeneous float aggregate or two
  integers and silently wrong for a long beside a double. Unions are
  refused rather than imitated.

Each is intended for upstream; when one lands there, its branch is
deleted here and the next merge from upstream carries nothing for it.

---

ECL stands for Embeddable Common-Lisp. The ECL project aims to
produce an implementation of the Common-Lisp language which complies
to the ANSI X3J13 definition of the language.

The term embeddable refers to the fact that ECL includes a Lisp to C
compiler, which produces libraries (static or dynamic) that can be
called from C programs. Furthermore, ECL can produce standalone
executables from Lisp code and can itself be linked to your programs
as a shared library. It also features an interpreter for situations
when a C compiler isn't available.

ECL supports the operating systems Linux, FreeBSD, NetBSD, DragonFly
BSD, OpenBSD, Solaris (at least v. 9), Microsoft Windows (MSVC, MinGW
and Cygwin) and OSX, running on top of the Intel, Sparc, Alpha, ARM
and PowerPC processors.  Porting to other architectures should be
rather easy.