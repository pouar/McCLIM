;;; ---------------------------------------------------------------------------
;;;     Title: Page layout abstraction
;;;   Created: 2019-02-06 19:42
;;;    Author: Daniel Kochmański <daniel@turtleware.eu>
;;;   License: LGPL-2.1+ (See file 'Copyright' for details).
;;; ---------------------------------------------------------------------------
;;;
;;;  (c) copyright 2002 by Alexey Dejneka <adejneka@comail.ru>
;;;  (c) copyright 2019 by Daniel Kochmański <daniel@turtleware.eu>
;;;
;;; ---------------------------------------------------------------------------
;;;
;;; Page layout may has numerous properties which arrange things on a
;;; stream with having a broader picture in mind. Text on a page may
;;; have alignment and direction, margins, columns, paragraph settings
;;; and much more. This file is a backon abstraction which may be used
;;; to specify these things.
;;;
(in-package :clim-internals)

(defclass standard-page-layout ()
  ((%page-region :reader stream-page-region :writer (setf %page-region))
   (margins :initarg :text-margins :accessor stream-text-margins))
  (:default-initargs :text-margins '(:left   (:absolute 0)
                                     :top    (:absolute 0)
                                     :right  (:relative 0)
                                     :bottom (:relative 0))))

(defmethod initialize-instance :after ((instance standard-page-layout)
                                       &key text-margins text-margin)
  (macrolet ((thunk (edge default)
               `(unless (getf text-margins ,edge)
                  (setf (getf text-margins ,edge) ,default))))
    (thunk :left   '(:absolute 0))
    (thunk :top    '(:absolute 0))
    (thunk :right  (or text-margin '(:relative 0)))
    (thunk :bottom '(:relative 0))))

(defgeneric page-cursor-initial-position (stream)
  (:documentation "Returns two values: x and y initial position for a cursor on page.")
  (:method ((stream standard-page-layout))
    (with-bounding-rectangle* (min-x min-y max-x max-y)
        (stream-page-region stream)
      (declare (ignore max-x max-y))
      (values min-x min-y))))

(defgeneric page-cursor-final-position (stream)
  (:documentation "Returns two values: x and y final position for a cursor on page.")
  (:method ((stream standard-page-layout))
    (with-bounding-rectangle* (min-x min-y max-x max-y)
        (stream-page-region stream)
      (declare (ignore min-x min-y))
      (values max-x max-y))))

(defmethod slot-unbound (class (stream standard-page-layout) (slot (eql '%page-region))
                         &aux (sheet-region (sheet-region (or (pane-viewport stream)
                                                              stream))))
  (when (eql sheet-region +everywhere+)
    (let ((x2 (* 80 (text-style-width  (stream-text-style stream) stream)))
          (y2 (* 43 (text-style-height (stream-text-style stream) stream))))
      (setf sheet-region (make-rectangle* 0 0 x2 y2))))
  (with-bounding-rectangle* (x1 y1 x2 y2) sheet-region
    (macrolet ((thunk (margin edge sign direction)
                 `(if (eql (first ,margin) :absolute)
                      (parse-space stream (second ,margin) ,direction)
                      (,sign ,edge (parse-space stream (second ,margin) ,direction)))))
      (destructuring-bind (&key left top right bottom) (stream-text-margins stream)
        (setf (%page-region stream)
              (make-rectangle* (thunk left   x1 + :horizontal)
                               (thunk top    y1 + :vertical)
                               (thunk right  x2 - :horizontal)
                               (thunk bottom y2 - :vertical)))))))

(defmethod (setf sheet-region) :before (sheet-region (stream standard-page-layout))
  (unless (region-equal sheet-region (sheet-region stream))
    (slot-makunbound stream '%page-region)))

(defun valid-margin-spec-p (margins)
  (ignore-errors ; destructuring-bind may error; that yields invalid spec
    (destructuring-bind (&key left top right bottom) margins
      (flet ((margin-spec-p (m)
               (and (member (first m) '(:absolute :relative))
                    (not (null (second m))))))
        (every #'margin-spec-p (list left top right bottom))))))

(deftype margin-spec ()
  `(satisfies valid-margin-spec-p))

(defmethod (setf stream-text-margins) :before
    (new-margins (stream standard-page-layout)
     &aux (old-margins (stream-text-margins stream)))
  (macrolet ((thunk (edge)
               `(unless (getf new-margins ,edge)
                  (setf (getf new-margins ,edge)
                        (getf old-margins ,edge)))))
    (thunk :left)
    (thunk :top)
    (thunk :right)
    (thunk :bottom))
  (check-type new-margins margin-spec)
  (unless (equal new-margins old-margins)
    (slot-makunbound stream '%page-region)))

(defgeneric invoke-with-temporary-page (stream continuation &key margins move-cursor)
  (:method ((stream standard-page-layout) continuation &key margins (move-cursor t))
    (letf (((stream-text-margins stream) margins))
      (multiple-value-bind (cx cy) (stream-cursor-position stream)
        (funcall continuation stream)
        (unless move-cursor
          (setf (stream-cursor-position stream) (values cx cy)))))))

(defmacro with-temporary-margins
    ((stream &rest args
             &key (move-cursor t) (left nil lp) (right nil rp) (top nil tp) (bottom nil bp))
     &body body)
  (declare (ignore move-cursor))
  (setq stream (stream-designator-symbol stream '*standard-output*))
  (with-keywords-removed (args (:left :right :top :bottom))
    (with-gensyms (continuation margins)
      `(flet ((,continuation (,stream) ,@body))
         (declare (dynamic-extent #',continuation))
         (let (,margins)
           ,@(collect (margin)
               (when lp (margin `(setf (getf ,margins :left) ,left)))
               (when rp (margin `(setf (getf ,margins :right) ,right)))
               (when tp (margin `(setf (getf ,margins :top) ,top)))
               (when bp (margin `(setf (getf ,margins :bottom) ,bottom)))
               (margin))
           (invoke-with-temporary-page ,stream #',continuation :margins ,margins ,@args))))))


;;; Mixin is used to store text-style and ink when filling-output it is invoked.

(defclass %filling-output-graphics-state (gs-ink-mixin gs-text-style-mixin)
  ()
  (:default-initargs :ink +foreground-ink+ :text-style *default-text-style*))

(defclass filling-output-mixin (gs-ink-mixin gs-text-style-mixin)
  ((lbs :accessor line-break-strategy :initarg :line-break-strategy
        :documentation "T for a default word wrap or a list of break characters.")
   (alb :accessor after-line-break :initarg :after-line-break
        :documentation "Function accepting stream to call after the line break.")
   (ilb :accessor after-line-break-initially :initarg :after-line-break-initially
        :documentation "Flag whenever we execture alb on fresh newlines.")
   (slb :accessor after-line-break-subsequent :initarg :after-line-break-subsequent
        :documentation "Flag whenever we execture alb on soft newlines.")
   (gfs :reader graphics-state :initarg :gfs))
  (:default-initargs :line-break-strategy t
                     :gfs (make-instance '%filling-output-graphics-state)
                     :after-line-break nil
                     :after-line-break-initially nil
                     :after-line-break-subsequent t))

(defmacro filling-output ((stream &key
                                  (fill-width ''(80 :character))
                                  break-characters
				  after-line-break
                                  after-line-break-initially
                                  (after-line-break-subsequent t))
			  &body body)
  (setq stream (stream-designator-symbol stream '*standard-output*))
  `(with-temporary-margins (,stream :right (list :absolute ,fill-width))
     (letf (((stream-end-of-line-action ,stream) :wrap*)
            ((line-break-strategy ,stream) ,break-characters)
            ,@(when after-line-break
                `(((after-line-break ,stream) ,after-line-break)
                  ((after-line-break-initially ,stream) ,after-line-break-initially)
                  ((after-line-break-subsequent ,stream) ,after-line-break-subsequent)
                  ((graphics-state-ink (graphics-state ,stream)) (medium-ink ,stream))
                  ((graphics-state-text-style (graphics-state ,stream)) (medium-text-style ,stream)))))
       ,(when (and after-line-break after-line-break-initially)
          `(etypecase (after-line-break ,stream)
             (string   (write-string (after-line-break ,stream) ,stream))
             (function (funcall (after-line-break ,stream) ,stream nil))))
       ,@body)))

(defmacro indenting-output ((stream indent &key (move-cursor t)) &body body)
  (setq stream (stream-designator-symbol stream '*standard-output*))
  `(with-temporary-margins (,stream :left (list :absolute ,indent)
                                    :move-cursor ,move-cursor)
     ,@body))


;;; formatting functions
(defun format-textual-list (sequence printer
                            &key stream separator conjunction
                              suppress-separator-before-conjunction
                              suppress-space-after-conjunction)
  "Outputs the SEQUENCE of items as a \"textual list\" into
STREAM. PRINTER is a function of an item and a stream. Between each
two items the string SEPARATOR is placed. If the string CONJUCTION is
supplied, it is placed before the last item.

SUPPRESS-SEPARATOR-BEFORE-CONJUNCTION and
SUPPRESS-SPACE-AFTER-CONJUNCTION are non-standard."
  (orf stream *standard-output*)
  (orf separator ", ")
  (let* ((length (length sequence))
         (n-rest length))
    (map-repeated-sequence nil 1
                           (lambda (item)
                             (funcall printer item stream)
                             (decf n-rest)
                             (cond ((> n-rest 1)
                                    (princ separator stream))
                                   ((= n-rest 1)
                                    (if conjunction
                                        (progn
                                          (unless suppress-separator-before-conjunction
                                            (princ separator stream))
                                          (princ conjunction stream)
                                          (unless suppress-space-after-conjunction
                                            (princ #\space stream)))
                                        (princ separator stream)))))
                           sequence)))
