;;;; gui.lisp -- build a real UIKit view hierarchy from Lisp.
;;;;
;;;; Nothing here is compiled: it runs interpreted, and reaches UIKit through
;;;; the Objective-C runtime using ECL's dynamic FFI (libffi). That matters on
;;;; iOS, where FFI:C-INLINE is useless because it needs a C compiler.
;;;;
;;;; The app loads this file from the bundle at boot and sets *CANVAS* to the
;;;; UIView it wants us to build into.

(in-package :cl-user)

(defparameter *canvas* nil
  "Foreign pointer to the UIView the app hands us to build into.")

;;; ------------------------------------------------------------------
;;; The bridge: three C functions is the whole of it
;;;
;;; The app installs these three pointers for us. It has to, because the
;;; iOS build is static (--disable-shared), which leaves ENABLE_DLOPEN off,
;;; and SI:FIND-FOREIGN-SYMBOL then refuses to look anything up. Only symbol
;;; *lookup* is lost that way -- SI:CALL-CFUN goes through libffi and works
;;; perfectly well, so being handed the addresses is enough.
;;; ------------------------------------------------------------------

(defparameter *objc-get-class* nil "&objc_getClass, installed by the app.")
(defparameter *objc-sel-register* nil "&sel_registerName, ditto.")
(defparameter *objc-msg-send* nil "&objc_msgSend, ditto.")

(defun bridge-ready-p ()
  (and *objc-get-class* *objc-sel-register* *objc-msg-send*))

(defun @class (name)
  (si:call-cfun *objc-get-class* :pointer-void '(:cstring) (list name)))

(defun @sel (name)
  (si:call-cfun *objc-sel-register* :pointer-void '(:cstring) (list name)))

(defun send (receiver selector &key (returning :pointer-void) types args)
  "Send SELECTOR to RECEIVER.

objc_msgSend is declared variadic, but on Apple's arm64 ABI variadic arguments
go on the stack while fixed ones go in registers -- so Apple tells you to cast
it to the exact prototype at each call site. Handing libffi a non-variadic
signature per call is precisely that, not a workaround."
  (si:call-cfun *objc-msg-send* returning
                (list* :pointer-void :pointer-void types)
                (list* receiver (@sel selector) args)))

(defun @new (class-name)
  (send (send (@class class-name) "alloc") "init"))

(defun @str (text)
  (send (@class "NSString") "stringWithUTF8String:"
        :types '(:cstring) :args (list text)))

;;; ------------------------------------------------------------------
;;; Auto Layout
;;;
;;; Constraints are used rather than frames on purpose: anchors and constants
;;; are objects and CGFloats, so nothing has to pass a CGRect by value, which
;;; ECL's FFI cannot express.
;;; ------------------------------------------------------------------

(defun pin (view anchor to-view to-anchor &optional (constant 0.0d0))
  (send (send view anchor) "constraintEqualToAnchor:constant:"
        :types '(:pointer-void :double)
        :args (list (send to-view to-anchor) constant)))

(defun activate (constraints)
  (let ((array (send (@class "NSMutableArray") "array")))
    (dolist (constraint constraints)
      (send array "addObject:" :types '(:pointer-void) :args (list constraint)))
    (send (@class "NSLayoutConstraint") "activateConstraints:"
          :types '(:pointer-void) :args (list array))))

(defun clear-canvas ()
  (let ((subviews (send *canvas* "subviews")))
    (dotimes (i (send subviews "count" :returning :long))
      (send (send subviews "objectAtIndex:" :types '(:long) :args (list i))
            "removeFromSuperview"))))

;;; ------------------------------------------------------------------
;;; The demo
;;; ------------------------------------------------------------------

(defun build-demo-gui (&optional
                       (lines (list "Built from Lisp"
                                    "UILabel + UIStackView + NSLayoutConstraint"
                                    (format nil "~A ~A, ~D features"
                                            (lisp-implementation-type)
                                            (lisp-implementation-version)
                                            (length *features*)))))
  "Construct a UIStackView of UILabels inside *CANVAS*."
  (unless (bridge-ready-p)
    (return-from build-demo-gui "; the app did not install the objc_msgSend bridge"))
  (unless *canvas*
    (return-from build-demo-gui "; no canvas -- the app never handed one over"))
  (clear-canvas)
  (let ((stack (@new "UIStackView")))
    (send stack "setAxis:" :types '(:long) :args '(1))       ; vertical
    (send stack "setSpacing:" :types '(:double) :args '(4.0d0))
    (send stack "setTranslatesAutoresizingMaskIntoConstraints:"
          :types '(:byte) :args '(0))                        ; NO
    (dolist (text lines)
      (let ((label (@new "UILabel")))
        (send label "setText:" :types '(:pointer-void) :args (list (@str text)))
        (send label "setNumberOfLines:" :types '(:long) :args '(0))
        (send stack "addArrangedSubview:" :types '(:pointer-void)
              :args (list label))))
    (send *canvas* "addSubview:" :types '(:pointer-void) :args (list stack))
    (activate (list (pin stack "topAnchor" *canvas* "topAnchor" 4.0d0)
                    (pin stack "leadingAnchor" *canvas* "leadingAnchor" 8.0d0)
                    (pin stack "trailingAnchor" *canvas* "trailingAnchor" -8.0d0)))
    (format nil "built a UIStackView of ~D UILabel~:P from Lisp" (length lines))))
