(require 'json)
(require 'subr-x)
(require 'flycheck)
(require 'rx)

(defun d-fix-execute (fix)
  "Execute the instructions in FIX."
  (undo-boundary)
  (let ((saved-position (point-marker)))
    (dolist (step fix)
      ;; (message "Running command: %s" step)
      (let ((command (alist-get 'command step)))
	(cond
	 ((equal command "goto")
	  (goto-char 1)
	  (forward-line (1- (string-to-number (alist-get 'line step))))
	  (forward-char (1- (string-to-number (alist-get 'char step)))))
	 ((equal command "insert")
	  (insert (alist-get 'text step)))
	 ((equal command "delete")
	  (delete-char (string-to-number (alist-get 'count step))))
	 ((equal command "return")
	  (goto-char saved-position))
	 (t
	  (error "Unknown dautofix action: '%s'" command)))))
    (set-marker saved-position nil)
    (undo-boundary)
    (flycheck-clear)
    (flycheck-buffer)))

(defun d-fix-handle-dautofix-line (str)
  "Handle a line of output (STR) from dautofix."
  (let* (;; (debug-on-error t)
	 (result (json-read-from-string str))
	 (json-array-type 'list)
	 (fixes-str (alist-get 'fixes result)))
    (if fixes-str
	(let* ((fixes
		(let* ((json-key-type 'string))
		  (json-read-from-string fixes-str)))
	       (choice (completing-read "Select fix: " fixes nil t)))
	  (when choice
	    (d-fix-execute (json-read-from-string (json-encode (cdr (assoc choice fixes)))))))
      (message "No fixes available for this error."))))

(defun d-fix-id (id)
  "Fix the identifier ID."
  ;; (message "d-fix-id (%s)" id)
  (let (fn proc)
    (setq fn (make-temp-file "dfix"))
    (write-region nil nil fn)
    (setq proc
	  (make-process
	   :name "dautofix"
	   :command '("dautofix")
	   :filter (lambda (proc str)
		     (process-put
		      proc 'dfix-output
		      (concat
		       (process-get
			proc 'dfix-output)
		       str)))
	   :sentinel (lambda (proc evt)
		       (delete-file
			(process-get proc 'dfix-fn))
		       (run-with-idle-timer
			0 nil 'd-fix-handle-dautofix-line
			(process-get proc 'dfix-output)))
	   :noquery t))
    (process-put proc 'dfix-fn fn)
    (process-put proc 'dfix-output "")
    (process-send-string proc (json-encode `((id . ,id) (file . ,fn))))
    (process-send-string proc "\n")
    (process-send-eof proc)))

(defvar d-fix-error-message-regexps nil
  "Regular expressions for error messages used for extracting the identifier.")
(setq d-fix-error-message-regexps
      (list
       (rx "undefined identifier "
	   (opt "`")
	   (group (one-or-more (or (syntax word) (syntax symbol))))
	   (opt "`")
	   (or
	    eol
	    ", did you mean "))
       (rx "undefined identifier '"
	   (group (one-or-more (or (syntax word) (syntax symbol))))
	   "'"
	   (or
	    eol
	    ", did you mean "))
       (rx (any "'`")
	   (group (one-or-more (or (syntax word) (syntax symbol))))
	   (any "'`")
	   " is not defined, perhaps "
	   (or
	    "you need to import "
	    "`import "
	    ))
       (rx "no property "
	   (any "'`")
	   (group (one-or-more (or (syntax word) (syntax symbol))))
	   (any "'`")
	   " for ")
       (rx "template instance "
	   (one-or-more any)
	   " template "
	   (any "'`")
	   (group (one-or-more (or (syntax word) (syntax symbol))))
	   (any "'`")
	   " is not defined"
	   (or
	    eol
	    ", did you mean "))
       (rx "template "
	   (opt "`")
	   (one-or-more any)
	   "."
	   (group (one-or-more (or (syntax word) (syntax symbol))))
	   (opt "`")
	   " cannot deduce function from argument types")
       (rx "function "
	   (opt "`")
	   (one-or-more any)
	   "."
	   (group (one-or-more (or (syntax word) (syntax symbol))))
	   "("
	   (one-or-more any)
	   ")"
	   (opt "`")
	   " is not callable using argument types ")
       (rx (opt "`")
	   (one-or-more any)
	   "."
	   (group (one-or-more (or (syntax word) (syntax symbol))))
	   (opt "`")
	   " is not visible from module ")
       (rx "none of the overloads of "
	   (any "'`")
	   (group (one-or-more (or (syntax word) (syntax symbol))))
	   (any "'`")
	   " are callable using argument types ")
       (rx "no overload matches for "
	   (any "'`")
	   (group (one-or-more (or (syntax word) (syntax symbol))))
	   (any "'`"))))

(defun d-fix-handle-error-message (msg)
  "Process/fix the error message MSG."
  (when (cl-loop for re in d-fix-error-message-regexps
		 ;; do (message "Testing regular expression '%s' against string '%s'" re msg)
		 thereis (string-match re msg))
    (d-fix-id (match-string 1 msg))
    t))

(defun d-fix-thing-at-point ()
  "Fix the thing at point."
  (interactive)
  (if-let ((errors (flycheck-overlay-errors-at (point))))
      (unless (cl-loop for err in errors
		       thereis (d-fix-handle-error-message (flycheck-error-message err)))
	(user-error "Unrecognized error at point"))
    (d-fix-id (symbol-at-point))))

(provide 'dfix)
