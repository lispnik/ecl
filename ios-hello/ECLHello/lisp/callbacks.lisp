;;;; callbacks.lisp -- is dynamic symbol lookup alive now?
(in-package :cl-user)

(defun dlopen-demo ()
  (handler-case
      (let ((get-class (si:find-foreign-symbol "objc_getClass" :default
                                               :pointer-void 0)))
        (if (zerop (ffi:pointer-address get-class))
            "; objc_getClass resolved to NULL"
            (let ((ns-string (si:call-cfun get-class :pointer-void
                                           '(:cstring) '("NSString"))))
              (format nil "find-foreign-symbol works: objc_getClass #x~X -> NSString #x~X"
                      (ffi:pointer-address get-class)
                      (ffi:pointer-address ns-string)))))
    (error (e) (format nil "; find-foreign-symbol FAILED: ~A" e))))
