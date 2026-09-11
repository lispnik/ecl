;;;; -*- Mode: Lisp; Syntax: Common-Lisp; indent-tabs-mode: nil -*-
;;;; vim: set filetype=lisp tabstop=8 shiftwidth=2 expandtab:

;;;; Author:   Juan Jose Garcia-Ripoll
;;;; Author:   Daniel Kochmański
;;;; Created:  Fri Apr 14 11:13:17 CEST 2006
;;;; Contains: Foreign Function Interface regression tests

(in-package :cl-test)
(suite 'ffi)

;;; Date: 23/03/2006
;;; From: Klaus Falb
;;; Fixed: 26/02/2006 (juanjo)
;;; Description:
;;;
;;;     Callback functions have to be declared static so that there
;;;     are no conflicts among callbacks in different files.
;;;
;;; Fixed: 13/04/2006 (juanjo)
;;; Description:
;;;
;;;     Header <internal.h> should be included as <ecl/internal.h>
;;;
#-ecl-bytecmp
(test ffi.0001.callback
  (is
   (and (ensure-directories-exist "tmp/")
        (with-open-file (s "tmp/a.lsp" :direction :output
                           :if-exists :supersede
                           :if-does-not-exist :create)
          (print '(ffi:defcallback foo :void () nil) s))
        (with-open-file (s "tmp/b.lsp" :direction :output
                           :if-exists :supersede
                           :if-does-not-exist :create)
          (print '(ffi:defcallback foo :void () nil) s))
        (compile-file "tmp/a.lsp" :system-p t)
        (compile-file "tmp/b.lsp" :system-p t)
        (c:build-program "tmp/foo" :lisp-files
                         (list (compile-file-pathname "tmp/a.lsp" :type :object)
                               (compile-file-pathname "tmp/b.lsp" :type :object)))
        (probe-file (compile-file-pathname "tmp/foo" :type :program)))))

;;; Date: 29/07/2008
;;; From: Juajo
;;; Description:
;;;     Callback examples based on the C compiler
;;;
#-ecl-bytecmp
(test ffi.0002.callback-sffi-example
  (is
   (and (ensure-directories-exist "tmp/")
        (with-open-file (s "tmp/c.lsp" :direction :output
                           :if-exists :supersede
                           :if-does-not-exist :create)
          (print
           '(defun callback-user (callback arg)
             (ffi:c-inline (callback arg) (:pointer-void :int) :int "
int (*foo)(int) = (int (*)(int))#0;
@(return) = foo(#1);
"
              :one-liner nil :side-effects nil))
           s)
          (print
           '(ffi:defcallback ffi-002-foo :int ((a :int))
             (1+ a))
           s))
        (compile-file "tmp/c.lsp" :load t)
        (eql (callback-user (ffi:callback 'ffi-002-foo) 2) 3)
        t)))

;;; Date: 29/07/2008
;;; From: Juajo
;;; Description:
;;;     Callback examples based on the DFFI. Only work if this feature
;;;     has been linked in.
;;;
#+(and dffi (not ecl-bytecmp))
(test ffi.0003.callback-dffi-example
  (is
   (and (ensure-directories-exist "tmp/")
        (with-open-file (s "tmp/c.lsp" :direction :output
                           :if-exists :supersede
                           :if-does-not-exist :create)
          (print
           '(defun callback-user (callback arg)
             (ffi:c-inline (callback arg) (:pointer-void :int) :int "
int (*foo)(int) = (int (*)(int))#0;
@(return) = foo(#1);
"
              :one-liner nil :side-effects nil))
           s))
        (compile-file "tmp/c.lsp" :load t)
        (eval '(ffi:defcallback foo-002b :int ((a :int))
                (1+ a)))
        (eql (callback-user (ffi:callback 'foo-002b) 2) 3)
        t)))

;;; Date: 25/04/2010 (Juanjo)
;;; Description:
;;;      Regression test to ensure that two foreign data compare
;;;      EQUAL when their addresses are the same.
(test ffi.0004.foreign-data-equal
  (is
   (equal (ffi:make-pointer 1234 :void)
          (ffi:make-pointer 1234 :int))))

;;; Date: 2016-01-04 (jackdaniel)
;;; Description:
;;;     Regression test to ensure, that the string is properly
;;;     recognized as an array
(test ffi.0005.string-is-array
  (finishes
    (si::make-foreign-data-from-array "dan")))

;;; Date: 2019-12-16
;;; Description:
;;;     Regression test to ensure correct complex float handling by
;;;     the interface. On some platforms libffi is miscompiled to
;;;     mishandle complex float return values. See the commit message
;;;     in a commit ad5fe834.
#+complex-float
(test ffi.0006.complex-floats
  ;; dffi
  (let* ((arg #C(10.0s0 0.5s0))
         (expect (atanh arg)))
    (finishes (ffi:def-function "catanhf" ((x :csfloat))
                :returning :csfloat
                :module :default))
    (is (= expect (catanhf arg))))
  ;; sffi
  #-ecl-bytecmp
  (let* ((arg #C(10.0s0 0.5s0))
         (expect (atanh arg)))
    (finishes (ffi:def-function "catanhf" ((x :csfloat))
                :returning :csfloat))
    (compile 'catanhf)
    (is (= expect (catanhf arg)))))

;;; Date: 2026-06-14 (Marius Gerbershagen)
;;; Description:
;;;     Check that a few basic functions of the UFFI interface work
;;;     when backed by the SFFI interface
(test ffi.0007.uffi-via-sffi
  (with-open-file (s "ffi-0007-uffi-via-sffi.lsp" :direction :output
                                          :if-exists :supersede
                                          :if-does-not-exist :create)
    (mapc #'(lambda (form) (print form s))
          '((in-package #:cl-test)
            (ffi:clines "
int baz = 3;

typedef struct {
  int x;
  double y;
} foo_struct;

foo_struct the_struct = { 42, 3.2 };

int foo () {
  return baz;
}")
            (ffi:def-struct foo-struct
             (x :int)
             (y :double))
            (ffi:def-function ("foo" foo) ()
             :returning :int
             :module nil)
            (ffi:def-foreign-var ("baz" *baz*) :int nil)
            (ffi:def-foreign-var ("the_struct" *the-struct*) foo-struct nil))))
  (is (not (null (compile-file "ffi-0007-uffi-via-sffi.lsp" :load t))))
  (is (eval '(eql *baz* 3)))
  (is (eval '(eql (incf *baz*) 4)))
  (is (eval '(eql *baz* 4)))
  (is (eql (foo) 4))
  (is (eql (ffi:get-slot-value *the-struct* 'foo-struct 'x) 42))
  (is (eql (ffi:get-slot-value *the-struct* 'foo-struct 'y) 3.2d0))
  (is (eql (setf (ffi:get-slot-value *the-struct* 'foo-struct 'x) 43) 43))
  (is (eql (ffi:get-slot-value *the-struct* 'foo-struct 'x) 43)))

;;; Date: 2026-09-11 (Matthew Kennedy)
;;; Description:
;;;
;;;     The dynamic FFI passes and returns structures by value. Before
;;;     this, SI:CALL-CFUN accepted only the scalar tags, so a caller
;;;     had to decompose a structure into the scalars it is made of and
;;;     hope the ABI put them in the same registers -- which on AArch64
;;;     is true for a homogeneous float aggregate and for two integers,
;;;     and silently false for a long next to a double. libffi knows the
;;;     rules; these hand it the layout and check it applies them.
;;;
;;;     The shapes are chosen for what AArch64 does with them: two and
;;;     four doubles ride in vector registers both ways; two longs in
;;;     x0/x1; a long beside a double splits across x0 and v0; 24 bytes
;;;     of longs go by pointer and come back through x8; nesting and an
;;;     array member must flatten to the same classification as the
;;;     equivalent flat structure.
#-ecl-bytecmp
(test ffi.0008.dffi-structures-by-value
  (with-open-file (s "ffi-0008-structs.lsp" :direction :output
                                            :if-exists :supersede
                                            :if-does-not-exist :create)
    (mapc #'(lambda (form) (print form s))
          '((in-package #:cl-test)
            (ffi:clines "
#include <math.h>
typedef struct { double x, y; } pt;
typedef struct { double x, y, w, h; } rect;
typedef struct { long location, length; } range;
typedef struct { long a; double b; } mixed;
typedef struct { long a, b, c; } big;
typedef struct { pt a, b; } line;
typedef struct { signed char tag; int values[3]; } tagged;

pt pt_scale(pt p, double k) { pt r = { p.x * k, p.y * k }; return r; }
double rect_area(rect r) { return r.w * r.h; }
rect rect_make(double x, double y, double w, double h) { rect r = { x, y, w, h }; return r; }
long range_end(range r) { return r.location + r.length; }
range range_make(long location, long length) { range r = { location, length }; return r; }
double mixed_sum(mixed m) { return m.a + m.b; }
mixed mixed_make(long a, double b) { mixed m = { a, b }; return m; }
long big_sum(big b) { return b.a + b.b + b.c; }
big big_make(long a, long b, long c) { big r = { a, b, c }; return r; }
double line_length(line l) { double dx = l.b.x - l.a.x, dy = l.b.y - l.a.y; return sqrt(dx * dx + dy * dy); }
int tagged_sum(tagged t) { return t.tag + t.values[0] + t.values[1] + t.values[2]; }
pt apply_pt(pt (*f)(pt), pt p) { return f(p); }
mixed apply_mixed(mixed (*f)(mixed, long), mixed m, long k) { return f(m, k); }
")
            (ffi:def-struct ffi-0008-pt (x :double) (y :double))
            (ffi:def-struct ffi-0008-rect (x :double) (y :double) (w :double) (h :double))
            (ffi:def-struct ffi-0008-range (location :long) (length :long))
            (ffi:def-struct ffi-0008-mixed (a :long) (b :double))
            (ffi:def-struct ffi-0008-big (a :long) (b :long) (c :long))
            (ffi:def-struct ffi-0008-line (a ffi-0008-pt) (b ffi-0008-pt))
            (ffi:def-struct ffi-0008-tagged (tag :byte) (values (:array :int 3)))
            ;; SI:CALL-CFUN reads designators in C and cannot resolve a
            ;; name, so it is handed the (:STRUCT ...) list the name stands for.
            (defun ffi-0008-type (name) (ffi::%convert-to-ffi-type name))
            (defmacro ffi-0008-address (c-name)
              `(ffi:c-inline () () :pointer-void ,(format nil "(void*)&~a" c-name)
                             :one-liner t))
            (defun ffi-0008-make (type &rest slots)
              (let ((object (ffi:allocate-foreign-object type)))
                (loop for (slot value) on slots by #'cddr
                      do (setf (ffi:get-slot-value object type slot) value))
                object))
            (defun ffi-0008-slot (object type slot)
              (ffi:get-slot-value object type slot))
            (defun ffi-0008-call (c-name return-type arg-types &rest args)
              (si::call-cfun (ffi-0008-address-of c-name)
                             (ffi-0008-type return-type)
                             (mapcar #'ffi-0008-type arg-types)
                             args))
            (defun ffi-0008-address-of (c-name)
              (cond ((string= c-name "pt_scale") (ffi-0008-address "pt_scale"))
                    ((string= c-name "rect_area") (ffi-0008-address "rect_area"))
                    ((string= c-name "rect_make") (ffi-0008-address "rect_make"))
                    ((string= c-name "range_end") (ffi-0008-address "range_end"))
                    ((string= c-name "range_make") (ffi-0008-address "range_make"))
                    ((string= c-name "mixed_sum") (ffi-0008-address "mixed_sum"))
                    ((string= c-name "mixed_make") (ffi-0008-address "mixed_make"))
                    ((string= c-name "big_sum") (ffi-0008-address "big_sum"))
                    ((string= c-name "big_make") (ffi-0008-address "big_make"))
                    ((string= c-name "line_length") (ffi-0008-address "line_length"))
                    ((string= c-name "tagged_sum") (ffi-0008-address "tagged_sum"))
                    ((string= c-name "apply_pt") (ffi-0008-address "apply_pt"))
                    ((string= c-name "apply_mixed") (ffi-0008-address "apply_mixed"))
                    (t (error "no such helper ~a" c-name))))
            ;; Callbacks through the dynamic path, so libffi closures whose
            ;; arguments and results are structures. Under EVAL because the
            ;; compiler turns a DEFCALLBACK it sees into a static C function,
            ;; and that path takes elementary types only.
            (eval '(ffi:defcallback ffi-0008-flip ffi-0008-pt ((p ffi-0008-pt))
                    (ffi-0008-make 'ffi-0008-pt
                                   'x (ffi-0008-slot p 'ffi-0008-pt 'y)
                                   'y (ffi-0008-slot p 'ffi-0008-pt 'x))))
            (eval '(ffi:defcallback ffi-0008-stretch ffi-0008-mixed ((m ffi-0008-mixed) (k :long))
                    (ffi-0008-make 'ffi-0008-mixed
                                   'a (+ (ffi-0008-slot m 'ffi-0008-mixed 'a) k)
                                   'b (* (ffi-0008-slot m 'ffi-0008-mixed 'b) k)))))))
  (is (not (null (compile-file "ffi-0008-structs.lsp" :load t))))
  (flet ((make (type &rest slots) (apply #'ffi-0008-make type slots))
         (slot (object type slot) (ffi-0008-slot object type slot))
         (call (c-name return-type arg-types &rest args)
           (apply #'ffi-0008-call c-name return-type arg-types args)))
    ;; two doubles: v0, v1 in and out
    (let ((r (call "pt_scale" 'ffi-0008-pt '(ffi-0008-pt :double)
                   (make 'ffi-0008-pt 'x 1.5d0 'y -2d0) 4d0)))
      (is (= 6d0 (slot r 'ffi-0008-pt 'x)))
      (is (= -8d0 (slot r 'ffi-0008-pt 'y))))
    ;; four doubles: still a homogeneous aggregate, v0-v3 both ways
    (is (= 12d0 (call "rect_area" :double '(ffi-0008-rect)
                      (make 'ffi-0008-rect 'x 0d0 'y 0d0 'w 3d0 'h 4d0))))
    (let ((r (call "rect_make" 'ffi-0008-rect '(:double :double :double :double)
                   1d0 2d0 3d0 4d0)))
      (is (= 1d0 (slot r 'ffi-0008-rect 'x)))
      (is (= 4d0 (slot r 'ffi-0008-rect 'h))))
    ;; two longs: x0, x1
    (is (= 11 (call "range_end" :long '(ffi-0008-range)
                    (make 'ffi-0008-range 'location 6 'length 5))))
    (let ((r (call "range_make" 'ffi-0008-range '(:long :long) 6 5)))
      (is (= 6 (slot r 'ffi-0008-range 'location)))
      (is (= 5 (slot r 'ffi-0008-range 'length))))
    ;; a long and a double: x0 and v0. The shape a scalar decomposition
    ;; gets wrong, because it would put the double in x1.
    (is (= 44.5d0 (call "mixed_sum" :double '(ffi-0008-mixed)
                        (make 'ffi-0008-mixed 'a 42 'b 2.5d0))))
    (let ((r (call "mixed_make" 'ffi-0008-mixed '(:long :double) 7 0.25d0)))
      (is (= 7 (slot r 'ffi-0008-mixed 'a)))
      (is (= 0.25d0 (slot r 'ffi-0008-mixed 'b))))
    ;; 24 bytes of integers: passed by pointer, returned through x8
    (is (= 60 (call "big_sum" :long '(ffi-0008-big)
                    (make 'ffi-0008-big 'a 10 'b 20 'c 30))))
    (let ((r (call "big_make" 'ffi-0008-big '(:long :long :long) 1 2 3)))
      (is (= 1 (slot r 'ffi-0008-big 'a)))
      (is (= 2 (slot r 'ffi-0008-big 'b)))
      (is (= 3 (slot r 'ffi-0008-big 'c))))
    ;; nested: a pair of pairs of doubles is an aggregate of four
    (let ((l (ffi:allocate-foreign-object 'ffi-0008-line)))
      (setf (ffi:get-slot-value (ffi:get-slot-pointer l 'ffi-0008-line 'a) 'ffi-0008-pt 'x) 0d0
            (ffi:get-slot-value (ffi:get-slot-pointer l 'ffi-0008-line 'a) 'ffi-0008-pt 'y) 0d0
            (ffi:get-slot-value (ffi:get-slot-pointer l 'ffi-0008-line 'b) 'ffi-0008-pt 'x) 3d0
            (ffi:get-slot-value (ffi:get-slot-pointer l 'ffi-0008-line 'b) 'ffi-0008-pt 'y) 4d0)
      (is (= 5d0 (call "line_length" :double '(ffi-0008-line) l))))
    ;; an array member contributes its elements, and the padding after a
    ;; one-byte tag is libffi's to work out
    (let ((v (ffi:allocate-foreign-object 'ffi-0008-tagged)))
      (setf (ffi:get-slot-value v 'ffi-0008-tagged 'tag) 1)
      (let ((values (ffi:get-slot-pointer v 'ffi-0008-tagged 'values)))
        (setf (ffi:deref-array values '(:array :int 3) 0) 10
              (ffi:deref-array values '(:array :int 3) 1) 20
              (ffi:deref-array values '(:array :int 3) 2) 30))
      (is (= 61 (call "tagged_sum" :int '(ffi-0008-tagged) v))))
    ;; callbacks: a structure in, a structure out, through a libffi closure
    (let ((r (call "apply_pt" 'ffi-0008-pt '(:pointer-void ffi-0008-pt)
                   (ffi:callback 'ffi-0008-flip)
                   (make 'ffi-0008-pt 'x 1d0 'y 2d0))))
      (is (= 2d0 (slot r 'ffi-0008-pt 'x)))
      (is (= 1d0 (slot r 'ffi-0008-pt 'y))))
    (let ((r (call "apply_mixed" 'ffi-0008-mixed '(:pointer-void ffi-0008-mixed :long)
                   (ffi:callback 'ffi-0008-stretch)
                   (make 'ffi-0008-mixed 'a 40 'b 1.5d0) 2)))
      (is (= 42 (slot r 'ffi-0008-mixed 'a)))
      (is (= 3d0 (slot r 'ffi-0008-mixed 'b))))
    ;; the result is foreign data that reports the structure's size,
    ;; tagged with the type it was returned as
    (let ((r (call "range_make" 'ffi-0008-range '(:long :long) 1 2)))
      (is (equal (ffi-0008-type 'ffi-0008-range) (si::foreign-data-tag r))))))

;;; What the dynamic FFI refuses, and that it refuses rather than guesses.
;;; Self-contained: every refusal happens while the call is being prepared,
;;; before the function pointer is used, so a null one will do and nothing
;;; compiled in another test is needed.
(ffi:def-foreign-type ffi-0009-pt (:struct (x :double) (y :double)))

(test ffi.0009.dffi-structures-refused
  (let ((pt (ffi::%convert-to-ffi-type 'ffi-0009-pt))
        (fn (ffi:make-pointer 0 :void)))
    ;; not foreign data at all
    (signals error (si::call-cfun fn pt (list pt :double) (list 42 1d0)))
    ;; foreign data, but too small to be one of these
    (signals error (si::call-cfun fn pt (list pt :double)
                                  (list (ffi:allocate-foreign-object :int) 1d0)))
    ;; a union has no libffi description that is right for every ABI
    (signals error (si::call-cfun fn :void '((:union (a :long) (b :double)))
                                  (list (ffi:allocate-foreign-object 'ffi-0009-pt))))
    ;; an empty structure has no representation
    (signals error (si::call-cfun fn :void '((:struct))
                                  (list (ffi:allocate-foreign-object 'ffi-0009-pt))))
    ;; and the Lisp side resolves names but leaves the decision to C
    (is (equal pt (ffi::%convert-to-dffi-arg-type 'ffi-0009-pt)))
    (is (eq :pointer-void (ffi::%convert-to-dffi-arg-type '(* ffi-0009-pt))))
    (is (eq :pointer-void (ffi::%convert-to-dffi-arg-type '(:array :int 3))))))

;;; Date: 2026-09-11 (Matthew Kennedy)
;;; Description:
;;;
;;;     A dynamic callback is called on whatever thread the foreign code
;;;     likes. One ECL did not create has no environment, and asking for
;;;     it was a fatal internal error, so the executor now imports the
;;;     thread first. This calls a closure from a pthread Lisp has never
;;;     heard of; without the import the process dies rather than fails.
#-ecl-bytecmp
(test ffi.0010.dffi-callback-on-a-foreign-thread
  (with-open-file (s "ffi-0010-thread.lsp" :direction :output
                                           :if-exists :supersede
                                           :if-does-not-exist :create)
    (mapc #'(lambda (form) (print form s))
          '((in-package #:cl-test)
            (ffi:clines "
#include <pthread.h>
struct ffi_0010_job { int (*f)(int); int x; int result; };
static void *ffi_0010_run(void *p) {
  struct ffi_0010_job *job = p;
  job->result = job->f(job->x);
  return 0;
}
int ffi_0010_call_on_new_thread(int (*f)(int), int x) {
  struct ffi_0010_job job = { f, x, -1 };
  pthread_t thread;
  if (pthread_create(&thread, 0, ffi_0010_run, &job) != 0) return -2;
  pthread_join(thread, 0);
  return job.result;
}")
            (defun ffi-0010-address ()
              (ffi:c-inline () () :pointer-void "(void*)&ffi_0010_call_on_new_thread"
                            :one-liner t))
            (eval '(ffi:defcallback ffi-0010-double :int ((a :int)) (* 2 a))))))
  (is (not (null (compile-file "ffi-0010-thread.lsp" :load t))))
  (is (eql 42 (si::call-cfun (ffi-0010-address) :int '(:pointer-void :int)
                             (list (ffi:callback 'ffi-0010-double) 21)))))

;;; Date: 2026-09-11 (Matthew Kennedy)
;;; Description:
;;;
;;;     A dynamic callback has to outlive every collection between its
;;;     creation and its last call: the address is in foreign hands. The
;;;     closure record is malloc memory with a finalizer on the object
;;;     that wraps it, and that object must be reachable for as long as
;;;     the callback is -- it was once left out of the list that keeps it
;;;     so, and the first collection freed the record under a live
;;;     trampoline.
#+(and dffi (not ecl-bytecmp))
(test ffi.0011.dffi-callback-survives-a-collection
  (eval '(ffi:defcallback ffi-0011-triple :int ((a :int)) (* 3 a)))
  (let ((callback (ffi:callback 'ffi-0011-triple)))
    (dotimes (i 3)
      (si:gc t)
      (is (eql 42 (si::call-cfun callback :int '(:int) '(14)))))))

;;; Date: 2026-09-11 (Matthew Kennedy)
;;; Description:
;;;
;;;     SI:CALL-CFUN makes a variadic call when told how many arguments
;;;     are fixed. On AArch64 Darwin the variadic ones travel on the
;;;     stack, so a cif prepared as if they were fixed puts them in
;;;     registers the callee never reads -- which is why this needs
;;;     saying rather than being inferred. snprintf is the variadic
;;;     function every libc has.
#-ecl-bytecmp
(test ffi.0012.dffi-variadic-call
  (with-open-file (s "ffi-0012-variadic.lsp" :direction :output
                                             :if-exists :supersede
                                             :if-does-not-exist :create)
    (mapc #'(lambda (form) (print form s))
          '((in-package #:cl-test)
            (ffi:clines "#include <stdio.h>")
            (defun ffi-0012-snprintf ()
              (ffi:c-inline () () :pointer-void "(void*)&snprintf" :one-liner t)))))
  (is (not (null (compile-file "ffi-0012-variadic.lsp" :load t))))
  (let ((buffer (ffi:allocate-foreign-object :char 64)))
    ;; Three fixed -- the buffer, its size and the format -- then an int, a
    ;; string and a double, promoted the way C would promote them.
    (is (eql 8 (si::call-cfun (ffi-0012-snprintf) :int
                              '(:pointer-void :unsigned-long :cstring :int :cstring :double)
                              (list buffer 64 "%d %s %.1f" 42 "x" 2.5d0)
                              :default 3)))
    (is (string= "42 x 2.5" (ffi:convert-from-foreign-string buffer)))
    ;; An unpromoted variadic argument is refused, not passed wrongly.
    (signals error (si::call-cfun (ffi-0012-snprintf) :int
                                  '(:pointer-void :unsigned-long :cstring :float)
                                  (list buffer 64 "%f" 1.5)
                                  :default 3))
    ;; More fixed arguments than there are is nonsense, and says so.
    (signals error (si::call-cfun (ffi-0012-snprintf) :int
                                  '(:pointer-void :unsigned-long :cstring)
                                  (list buffer 64 "x")
                                  :default 4))))
