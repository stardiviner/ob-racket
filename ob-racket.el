;;; ob-racket.el --- Racket language support in Emacs Org-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2018 DEADB17
;; This code is based on on previous work from:
;; - wallyqs https://github.com/wallyqs/ob-racket
;; - hasu https://github.com/hasu/emacs-ob-racket
;; - xchrishawk https://github.com/xchrishawk/ob-racket

;; Author: DEADB17
;; Version: 1.0.0
;; Created: 2018-01-07
;; Keywords: literate programming, racket
;; Homepage: https://github.com/DEADB17/ob-racket

;; This file is not part of GNU Emacs

;;; License:

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Support for evaluating racket code in org-mode
;; See https://orgmode.org/manual/Working-with-source-code.html

;; Requirements:

;; - Racket, see http://racket-lang.org/
;; - either racket-mode or geiser

;; For racket-mode, see https://github.com/greghendershott/racket-mode
;; For geiser, see http://www.nongnu.org/geiser/

;;; Code:

(require 'ob)

;; add racket to languages supported by org
(defvar org-babel-tangle-lang-exts)
(add-to-list 'org-babel-tangle-lang-exts '("racket" . "rkt"))

(defcustom org-babel-racket-command "racket"
  "Name of command to use for executing Racket code."
  :group 'org-babel
  :version "25.3"
  :package-version '(Org . "9.1.6")
  :type 'string)

(defcustom org-babel-racket-hline-to "nil"
  "Replace hlines in incoming tables with this when translating to racket."
  :group 'org-babel
  :version "25.3"
  :package-version '(Org . "9.1.6")
  :type 'string)

(defcustom org-babel-racket-nil-to 'hline
  "Replace 'nil' in racket tables with this before returning."
  :group 'org-babel
  :version "25.3"
  :package-version '(Org . "9.1.6")
  :type 'symbol)

(defvar org-babel-default-header-args:racket
  '((:results . "output silent")
    (:lang . "racket"))
  "Default arguments when evaluating a Racket source block.
Defaulting `:results' `collection' to `output' as `value' is more
limited.
Defaulting `:results' `handling' to `silent' as it is handy for
just interactively checking that a Racket listing has been typed
in correctly.
Defaulting `:lang' to `racket' as it is the most common option.")

(defun org-babel-racket--table-or-string (results)
  "Convert RESULTS into an appropriate elisp value.
If RESULTS look like a table, then convert them into an Emacs-lisp table,
otherwise return the results as a string."
  (let ((res (org-babel-script-escape results)))
    (if (listp res)
        (mapcar
         (lambda (el)
           (if (equal el 'nil)
               org-babel-racket-nil-to el))
         res)
      res)))

(defun ob-racket--vars-to-values (vars)
  "Convers VARS to a string of racket code.
VARS are wrapped as define-values."
  (list
   (concat
    "(define-values ("
    (mapconcat (lambda (var) (format "%s" (car var))) vars " ")
    ") (values"
    (mapconcat (lambda (var)
                 (let ((val (cdr var)))
                   (format (if (listp val) " '%S" " %S") val))) vars "")
    "))")))

(defun ob-racket-expand-fmt (fmt &optional params)
  "Expands a format list `FMT', and return a string.
PARAMS
Substitutes symbols according to the `params` alist.
The `fmt` argument may also be a string, in which
case it is returned as is."
  (if (stringp fmt)
      fmt
    (mapconcat
     (lambda (x)
       (cond
        ((stringp x) x)
        ((eq x 'ln) "\n")
        ((eq x 'quot) "\"")
        ((eq x 'apos) "\'")
        ((symbolp x)
         (let ((p (cdr (assq x params))))
           (unless p
             (error "Key %s not in %S" x params))
           (format "%s" p)))
        (t (error "Expected string or symbol: %S" fmt))))
     fmt "")))

(defun org-babel-expand-body:racket (body params)
  "Expands BODY according to PARAMS, returning the expanded body."
  (let ((lang-line (cdr (assoc :lang params)))
        (pro (cdr (assoc :prologue params)))
        (epi (cdr (assoc :epilogue params)))
        (vars (org-babel--get-vars params))
        (var-defs nil))
    (when (> (length vars) 0)
      (if (or (string-prefix-p "racket" lang-line)
              (string-prefix-p "plai" lang-line)
              (string= "lazy" lang-line))
          (setq var-defs (ob-racket--vars-to-values vars))
        (display-warning
         'ob-racket
         ":var is only supported when :lang starts with `racket', `plai' or `lazy'")))
  (mapconcat #'identity
             (append
              (list (format "#lang %s\n" lang-line))
              (when pro (list (ob-racket-expand-fmt pro)))
              var-defs
              (list body)
              (when epi (list (ob-racket-expand-fmt epi))))
             "\n")))

(defun org-babel-execute:racket (body params)
  "Evaluate a `racket' code block.
BODY and PARAMS
Some custom header arguments are supported for extra control over how the
evaluation is to happen.
These are:
- :eval-file pathname (file for code to evaluate)
- :cmd `shell-command' (defaults to '(\"racket -u\" eval-file))
- :eval-fun lam-expr (as: in-fn out-fn -> result-string)
The `shell-command' may also be a list of strings that will be concatenated; the
list may also contain one of the following symbols:
- `eval-file', replaced with source pathname
- `obj-file', replaced with any target \"file\" pathname
For more control, the :eval-fun parameter may specify a lambda expression to
define how to process the block.
As special cases, :eval-fun may be specified as:
- \"body\", to have the result be the bare body content
- \"code\", to have the result be the expanded code
- \"file\", to have the result name a file containing the code"
  (let* ((eval-fun    (cdr (assoc :eval-fun params)))
         (result-type (cdr (assoc :result-type params)))
         (full-body   (org-babel-expand-body:racket
                       (cond
                        ((eq 'value result-type)  (format "(write (begin %s))" body))
                        ((eq 'output result-type) body)
                        (t (error "Expected :results of `output` or `value`")))
                       params))
         (result (cond
                  ((equal eval-fun "body")  body)
                  ((equal eval-fun "code")  full-body)
                  ((equal eval-fun "debug") (format "params=%S" params))
                  (t (let ((eval-file (or (cdr (assoc :eval-file params))
                                          (org-babel-temp-file "org-babel-" ".rkt"))))
                       (with-temp-file eval-file (insert full-body))
                       (cond
                        ((equal eval-fun "file") (org-babel-process-file-name eval-file t))
                        (t
                         (let* ((in-fn    (org-babel-process-file-name eval-file t))
                                (obj-file (cdr (assoc :file params)))
                                (out-fn   (and obj-file
                                               (org-babel-process-file-name obj-file t)))
                                (exec-f   (function
                                           (lambda (cmd)
                                             (message cmd)
                                             (shell-command-to-string cmd)))))
                           (cond
                            ((not eval-fun) (let ((sh-cmd
                                                   (let ((cmd-fmt
                                                          (or (cdr (assoc :cmd params))
                                                              '("racket -u " eval-file)))
                                                         (fmt-par
                                                          `((eval-file
                                                             . ,(shell-quote-argument in-fn))
                                                            (obj-file
                                                             . ,(and out-fn
                                                                     (shell-quote-argument out-fn))))))
                                                     (ob-racket-expand-fmt cmd-fmt fmt-par))))
                                              (message sh-cmd)
                                              (shell-command-to-string sh-cmd)))
                            ((listp eval-fun) (funcall (eval eval-fun t) in-fn out-fn))
                            (t (error "Expected lambda expression for :eval-fun")))))))))))
    (org-babel-reassemble-table
     (org-babel-result-cond (cdr (assq :result-params params))
       result
       (org-babel-racket--table-or-string result))
     (org-babel-pick-name (cdr (assq :colname-names params))
                          (cdr (assq :colnames params)))
     (org-babel-pick-name (cdr (assq :rowname-names params))
                          (cdr (assq :rownames params))))))

(defun org-babel-prep-session:racket (session params)
  "Not implemented.  SESSION and PARAMS are discarded."
  (error "`racket` presently does not support sessions"))

(provide 'ob-racket)

;;; ob-racket.el ends here
