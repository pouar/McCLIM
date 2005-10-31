(defpackage :clim-postscript-tests
  (:use :clim :clim-lisp))
(in-package :clim-postscript-tests)

(let ((psfilename "/tmp/clim-postscript-test.ps")
      (epsfilename "/tmp/clim-postscript-test.eps"))
  (unwind-protect
       (progn
         (with-open-file (s psfilename :direction :output :if-exists :supersede)
           (with-output-to-postscript-stream (s s :device-type :a4)
             (draw-text* s "Hello, World!" 20 20)))
         (with-open-file (s psfilename :direction :input)
           (let ((first-line (read-line s)))
             (assert (eql (mismatch first-line "%!PS-Adobe-") 11))
             (assert (null (position #\Space first-line)))
             (do ((line (read-line s) (read-line s)))
                 ((not (eql (mismatch line "%%") 2)) 
                  (error "Failed to find bounding box"))
               (when (eql (mismatch line "%%BoundingBox: ") 15)
                 (with-input-from-string (string line :start 15)
                   (let ((llx (read string))
                         (lly (read string))
                         (urx (read string))
                         (ury (read string)))
                     (assert (numberp llx))
                     (assert (numberp lly))
                     (assert (numberp urx))
                     (assert (numberp ury))
                     (return t)))))))
         (with-open-file (s epsfilename :direction :output :if-exists :supersede)
           (with-output-to-postscript-stream (s s :device-type :eps)
             (draw-rectangle* s 1 1 19 21)))
         (with-open-file (s epsfilename :direction :input)
           (let ((first-line (read-line s)))
             (assert (eql (mismatch first-line "%!PS-Adobe-") 11))
             (assert (search "EPSF" first-line))
             (do ((line (read-line s) (read-line s)))
                 ((not (eql (mismatch line "%%") 2)) 
                  (error "Failed to find bounding box"))
               (when (eql (mismatch line "%%BoundingBox: ") 15)
                 (with-input-from-string (string line :start 15)
                   (let ((llx (read string))
                         (lly (read string))
                         (urx (read string))
                         (ury (read string)))
                     (assert (numberp llx))
                     (assert (numberp lly))
                     (assert (numberp urx))
                     (assert (numberp ury))
                     (assert (>= 20 (- urx llx) 18))
                     (assert (>= 22 (- ury lly) 20))
                     (return t))))))))
    (delete-file psfilename)
    (delete-file epsfilename)))
