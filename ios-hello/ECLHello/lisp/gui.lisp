;;;; gui.lisp -- build a UIKit interface from Lisp, and wire it back to Lisp.
;;;;
;;;; Interpreted, through the Objective-C runtime, using ECL's dynamic FFI.
;;;; FFI:C-INLINE is unavailable here because it needs a C compiler, but
;;;; SI:CALL-CFUN builds its call frame at runtime through libffi and does not.
;;;;
;;;; Callbacks come back the other way through LispTarget, an Objective-C
;;;; object carrying a Lisp form. The form is read on every call, so redefining
;;;; ON-TAP changes what the button does without rebuilding anything.

(in-package :cl-user)

(defparameter *canvas* nil
  "Foreign pointer to the UIView the app gives us to build into.")

;;; ------------------------------------------------------------------
;;; The bridge: three C functions
;;;
;;; Resolved here rather than handed in by the app. That needs
;;; SI:FIND-FOREIGN-SYMBOL to work in a statically linked image, which took two
;;; fixes: ENABLE_DLOPEN is defined for the cross builds even though they are
;;; static, and ecl_library_symbol now asks for RTLD_DEFAULT rather than a null
;;; handle, which is not the global scope on Darwin.
;;; ------------------------------------------------------------------

(defun foreign-fn (name)
  (let ((pointer (si:find-foreign-symbol name :default :pointer-void 0)))
    (when (ffi:null-pointer-p pointer)
      (error "cannot resolve foreign symbol ~A" name))
    pointer))

(defvar *objc-get-class* (foreign-fn "objc_getClass"))
(defvar *objc-sel-register* (foreign-fn "sel_registerName"))
(defvar *objc-msg-send* (foreign-fn "objc_msgSend"))

(defun @nil () (ffi:make-null-pointer :void))

(defun @class (name)
  (si:call-cfun *objc-get-class* :pointer-void '(:cstring) (list name)))

(defun @sel (name)
  (si:call-cfun *objc-sel-register* :pointer-void '(:cstring) (list name)))

(defun send (receiver selector &key (returning :pointer-void) types args)
  "Send SELECTOR to RECEIVER.

objc_msgSend is variadic, but Apple's arm64 ABI puts variadic arguments on the
stack and fixed ones in registers, so Apple's own guidance is to cast it to the
exact prototype per call site. A non-variadic libffi signature per call is
precisely that."
  (si:call-cfun *objc-msg-send* returning
                (list* :pointer-void :pointer-void types)
                (list* receiver (@sel selector) args)))

(defun @new (class-name)
  (send (send (@class class-name) "alloc") "init"))

(defun @str (text)
  (send (@class "NSString") "stringWithUTF8String:"
        :types '(:cstring) :args (list text)))

(defun @to-string (ns-string)
  "COPY-SEQ is not decoration: -UTF8String points into storage the NSString
owns, and ECL's :cstring conversion aliases that buffer rather than copying it."
  (copy-seq (send ns-string "UTF8String" :returning :cstring)))

;;; ------------------------------------------------------------------
;;; Auto Layout
;;;
;;; Constraints rather than frames, because anchors are objects and constants
;;; are CGFloats -- nothing has to pass a CGRect by value, which ECL's FFI
;;; cannot express. That is the ABI hole strategy 6 exists to fill.
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
;;; The interface
;;; ------------------------------------------------------------------

(defconstant +touch-up-inside+ 64)      ; UIControlEventTouchUpInside

(defvar *taps* 0)
(defvar *status-label* nil)

(defun set-status (text)
  (when *status-label*
    (send *status-label* "setText:"
          :types '(:pointer-void) :args (list (@str text)))))

(defun slow-fib (n)
  "The same function, interpreted, for comparison."
  (if (< n 2) n (+ (slow-fib (- n 1)) (slow-fib (- n 2)))))

(defmacro millis (&body body)
  "Values of BODY's result and how many milliseconds it took."
  (let ((start (gensym)) (value (gensym)))
    `(let* ((,start (get-internal-real-time))
            (,value (progn ,@body)))
       (values ,value
               (round (* 1000 (- (get-internal-real-time) ,start))
                      internal-time-units-per-second)))))

(defun on-tap ()
  "What the button does. Redefine this and the next tap picks it up -- the form
LispTarget carries is read on every call."
  (incf *taps*)
  (multiple-value-bind (fast fast-ms) (millis (aot-fib 22))     ; native, aot.o
    (multiple-value-bind (slow slow-ms) (millis (slow-fib 22))  ; bytecode
      (declare (ignore slow))
      (set-status
       (format nil "tap ~D: fib(22) = ~D~%compiled ~D ms, interpreted ~D ms (~
                    ~:[~;~:*~,1Fx~])"
               *taps* fast fast-ms slow-ms
               (and (plusp fast-ms) (/ slow-ms (float fast-ms)))))))
  *taps*)

(defun add-label (stack text)
  (let ((label (@new "UILabel")))
    (send label "setText:" :types '(:pointer-void) :args (list (@str text)))
    (send label "setNumberOfLines:" :types '(:long) :args '(0))
    (send stack "addArrangedSubview:" :types '(:pointer-void) :args (list label))
    label))

(defun build-demo-gui ()
  "A UIStackView holding a label and a working UIButton, built from Lisp."
  (unless *canvas*
    (return-from build-demo-gui "; no canvas -- the app never handed one over"))
  (clear-canvas)
  (setf *taps* 0)
  (let ((stack (@new "UIStackView")))
    (send stack "setAxis:" :types '(:long) :args '(1))      ; vertical
    (send stack "setSpacing:" :types '(:double) :args '(6.0d0))
    (send stack "setTranslatesAutoresizingMaskIntoConstraints:"
          :types '(:byte) :args '(0))

    (setf *status-label* (add-label stack "Built from Lisp. Press the button."))

    ;; A real UIButton whose action lands in Lisp.
    (let ((button (send (@class "UIButton") "buttonWithType:"
                        :types '(:long) :args '(1)))
          (target (send (@class "LispTarget") "targetWithForm:"
                        :types '(:pointer-void)
                        :args (list (@str "(on-tap)")))))
      (send button "setTitle:forState:"
            :types '(:pointer-void :long)
            :args (list (@str "Run compiled fib") 0))
      (send button "addTarget:action:forControlEvents:"
            :types '(:pointer-void :pointer-void :long)
            :args (list target (@sel "fire:") +touch-up-inside+))
      (send stack "addArrangedSubview:" :types '(:pointer-void)
            :args (list button))

      (send *canvas* "addSubview:" :types '(:pointer-void) :args (list stack))
      (activate (list (pin stack "topAnchor" *canvas* "topAnchor" 4.0d0)
                      (pin stack "leadingAnchor" *canvas* "leadingAnchor" 8.0d0)
                      (pin stack "trailingAnchor" *canvas* "trailingAnchor" -8.0d0)))

      ;; Prove the wiring without needing a finger: UIKit's own dispatch.
      (send button "sendActionsForControlEvents:"
            :types '(:long) :args (list +touch-up-inside+))))

  (format nil "UI built from Lisp; UIKit dispatched one action, Lisp counted ~D"
          *taps*))
