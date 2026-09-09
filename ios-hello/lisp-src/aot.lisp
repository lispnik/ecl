;;;; aot.lisp -- the compiled half.
;;;;
;;;; Never loaded at runtime. build-aot.sh compiles it on the host with the C
;;;; toolchain pointed at an iOS SDK, and the object is linked into the app.
;;;;
;;;; Two reasons to put something here rather than in a bundled .lisp file.
;;;; It runs as native code instead of bytecode, which is the difference
;;;; between an interactive image and a slow one. And FFI:DEFCALLBACK, with
;;;; FFI::*USE-DFFI* bound to NIL, emits an ordinary C function -- so the
;;;; callback needs no executable memory at runtime, which is the one thing
;;;; iOS will not grant.

(in-package :cl-user)

(defun aot-fib (n)
  "Deliberately naive: the point is to be called a lot."
  (declare (optimize (speed 3) (safety 0) (debug 0))
           (type fixnum n))
  (if (< n 2) n (+ (aot-fib (- n 1)) (aot-fib (- n 2)))))

(ffi:defcallback aot-callback :int ((n :int))
  (aot-fib n))
