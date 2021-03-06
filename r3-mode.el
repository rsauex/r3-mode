;;; r3-mode.el --- major mode for REBOL 3 files  -*- lexical-binding: t -*-

;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'comint)
(require 'thingatpt)

(defgroup r3 nil
  "Support for the REBOL3 programming language, <http://www.rebol.com/>"
  :group 'languages)

(defcustom r3-rebol-command "r3"
  "The location of the rebol interpreter on your system."
  :type 'string
  :group 'r3)

(defcustom r3-rebol-ide-file (concat (file-name-directory load-file-name) "ide.r")
  "Location of the rebol ide addon."
  :type 'string
  :group 'r3)

(defcustom r3-indent-offset 4
  "Number of spaces per indent level."
  :type 'integer
  :group 'r3)

(defcustom r3-mode-hook nil
  "The hook list for r3-mode."
  :type 'hook
  :group 'r3)

(defvar r3-rebol-process
  (start-process "rebol3-background" nil r3-rebol-command)
  "A handle on the background r3 process that will be doing our dynamic work.")

(defvar r3-rebol-ide-header
  "R3IDE-"
  "The regexp defining a message from the r3 ide component. Each message should start with a line like this.")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Interactive

(defun r3-sanitize-fname (fname)
  (replace-regexp-in-string "^\\(.*?\\):" "/\\1" fname))

(defun r3-trim (string)
  (replace-regexp-in-string "^\s+\\|\s+$" "" string))

(defun r3-to-oneline (string)
  (replace-regexp-in-string "[ \t\r\n]+" " " string))

(defun r3-strip-by-face (fontified-string face)
  (if (text-property-any 0 (length fontified-string) 'face face fontified-string)
      (let ((str (cl-coerce fontified-string 'list)))
        (cl-coerce (cl-loop for c in str
                            for i from 0
                            unless (eq face (get-text-property i 'face fontified-string)) collect c)
                   'string))
    fontified-string))

(defun r3-process-filter (proc msg)
  "Receives messages `MSG' from the r3 background process `PROC'.
Processes might send responses in 'bunches', rather than one complete response,
which is why we need to collect them, then split on an ending flag of some sort.
Currently, that's the REPL prompt '^>> '"
  (let ((buf ""))
    (setf buf (concat buf msg))
    (when (string-match ">> $" msg)
      (mapc #'r3-ide-directive (split-string buf "^>> "))
      (setf buf ""))))

(defun r3-send! (string)
  "Shortcut function to send a message `STRING' to the background r3 interpreter process."
  (process-send-string r3-rebol-process (concat string "\n")))

(r3-send! (concat "do %" (r3-sanitize-fname r3-rebol-ide-file)))
(set-process-filter r3-rebol-process #'r3-process-filter)
(add-hook 'after-change-functions #'r3-after-change)

(defun r3-ide-directive (msg)
  (let* ((raw-lines (butlast (split-string msg "\r?\n")))
         ;; the linux edition seems to return the function call before its output. Might also be an Emacs version issue.
         (lines (if (eq system-type 'gnu/linux) (cl-rest raw-lines) raw-lines)))
    (when lines
      (cond
       ;; TODO: fix
       ;; ((string-match "NEW-KEYWORDS: \\(.*\\)" (cl-first lines))
       ;;  (let ((type (intern (match-string 1 (cl-first lines)))))
       ;;    (setf (gethash type r3-highlight-symbols) (cl-rest lines))
       ;;    (r3-set-fonts)))
       ((string-match "HELP: \\(.*\\)" (cl-first lines))
        (get-buffer-create "*r3-help*")
        (with-current-buffer "*r3-help*"
          (kill-region (point-min) (point-max))
          (insert ";;; " (match-string 1 (cl-first lines)) " ;;;\n\n")
          (mapc (lambda (l) (insert l) (insert "\n")) (cl-rest lines))
          (r3-help-mode))
        (pop-to-buffer "*r3-help*"))
       ((string-match "SOURCE" (cl-first lines))
        (ignore-errors (kill-buffer "*r3-source*"))
        (get-buffer-create "*r3-source*")
        (with-current-buffer "*r3-source*"
          (mapc (lambda (l) (insert l) (insert "\n")) (cl-rest lines))
          (r3-source-mode))
        (pop-to-buffer "*r3-source*"))))))

(defun r3-help (word)
  (interactive (list (save-excursion
                       (let ((start (progn (beginning-of-sexp) (point)))
                             (end (progn (re-search-forward "[ \t]"))))
                         (r3-trim (buffer-substring start end))))))
  (r3-send! (format "ide/show-help %s" word)))

(defun r3-source (word)
  (interactive (list (thing-at-point 'word)))
  (r3-send! (format "ide/show-source %s" word)))

(defun r3-send-region (start end)
  (interactive (list (region-beginning) (region-end)))
  (let ((buffer (get-buffer "*rebol*")))
    (when buffer
      (let ((reg (buffer-substring start end))
            (tmp (make-temp-file "r3-send-" nil ".r")))
        (with-temp-file tmp
          (insert "REBOL [ title: \"Region insertion from r3-mode\" ]\n\n")
          (insert reg))
        (process-send-string
         (get-buffer-process buffer)
         (concat "do %"
                 (r3-sanitize-fname tmp)
                 "\n"))))))

(defun r3-after-change (start end len)
  (when (eq 'r3-mode major-mode)
    (message "Computing arg hint...")
    (save-excursion
      (let ((end (point)))
        (ignore-errors (backward-sexp))
        (let ((wd (r3-trim (buffer-substring (point) end))))
          (unless (string-match " " wd)
            (message "Showing arg hints for: '%s'" wd)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Syntax

(defvar r3-mode-syntax-table
  (let ((st (make-syntax-table)))

    ;; Symbol constituents
    (modify-syntax-entry ?\? "_   " st)
    (modify-syntax-entry ?\! "_   " st)
    (modify-syntax-entry ?\. "_   " st)
    (modify-syntax-entry ?\+ "_   " st)
    (modify-syntax-entry ?\- "_   " st)
    (modify-syntax-entry ?\* "_   " st)
    (modify-syntax-entry ?\& "_   " st)
    (modify-syntax-entry ?\| "_   " st)
    (modify-syntax-entry ?\= "_   " st)
    (modify-syntax-entry ?\_ "_   " st)
    (modify-syntax-entry ?\/ "_   " st)
    (modify-syntax-entry ?\' "_   " st)
    
    ;; Expression suffixes
    (modify-syntax-entry ?\: "'   " st)
    (modify-syntax-entry ?\# "'   " st)
    (modify-syntax-entry ?\% "'   " st)
    
    ;; Parenthesis
    (modify-syntax-entry ?\( "()  " st)
    (modify-syntax-entry ?\) ")(  " st)
    (modify-syntax-entry ?\[ "(]  " st)
    (modify-syntax-entry ?\] ")[  " st)

    ;; Other
    (modify-syntax-entry ?\\ ".   " st)
    
    ;; Escape
    (modify-syntax-entry ?^ "\\   " st)
    
    ;; Comments
    (modify-syntax-entry ?\n ">   " st)
    (modify-syntax-entry ?\; "<   " st)
    st)
  "Syntax table used in `r3-mode' buffers.")

(defun r3-last-brace-p (start end)
  "Return non-nil when a closing brace at position END closes the string starting at position START."
  (save-excursion
    (let ((level 0)
          (pos (1+ start)))
      (while (< pos end)
        (cond
         ((eq ?^ (char-after pos))
          (cl-incf pos))
         ((eq ?{ (char-after pos))
          (cl-incf level))
         ((eq ?} (char-after pos))
          (cl-decf level)))
        (cl-incf pos))
      (= 0 level))))

(defconst r3-syntax-propertize
  (syntax-propertize-rules
   ("'" (0 (let ((before-char (char-before (match-beginning 0))))
             (if (or (null before-char)
                     (let ((before-char-syntax (char-syntax before-char)))
                       (not (or (eq ?w before-char-syntax)
                                (eq ?_ before-char-syntax)))))
                 (string-to-syntax "'")
               (string-to-syntax "_")))))
   ("{" (0 (unless (nth 8 (save-excursion (syntax-ppss (match-beginning 0))))
             (string-to-syntax "|"))))
   ("}" (0 (let ((ppss (save-excursion (syntax-ppss (match-beginning 0)))))
             (when (and (eq t (nth 3 ppss))
                        (r3-last-brace-p (nth 8 ppss) (match-beginning 0)))
               (string-to-syntax "|")))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Highlighting

(defvar r3-highlight-symbols (make-hash-table)
  "Highlighting symbol table. Each key keeps a list of highlighted words in a particular category.")

(setf
 (gethash 'constants r3-highlight-symbols) (list "none" "true" "false")
 (gethash 'functions r3-highlight-symbols) (list "context" "func" "funct" "does" "use" "object" "module" "cause-error" "default" "secure" "repend" "join" "reform" "info?" "exists?" "size?" "modified?" "suffix?" "dir?" "dirize" "make-dir" "script?" "file-type?" "split-path" "intern" "load" "save" "import" "probe" "??" "boot-print" "loud-print" "spec-of" "body-of" "words-of" "values-of" "types-of" "title-of" "decode-url" "any-block?" "any-string?" "any-function?" "any-word?" "any-path?" "any-object?" "number?" "series?" "scalar?" "true?" "quote" "decode" "encode" "encoding?" "to-logic" "to-integer" "to-decimal" "to-percent" "to-money" "to-char" "to-pair" "to-tuple" "to-time" "to-date" "to-binary" "to-string" "to-file" "to-email" "to-url" "to-tag" "to-bitset" "to-image" "to-vector" "to-block" "to-paren" "to-path" "to-set-path" "to-get-path" "to-lit-path" "to-map" "to-datatype" "to-typeset" "to-word" "to-set-word" "to-get-word" "to-lit-word" "to-refinement" "to-issue" "to-command" "to-closure" "to-function" "to-object" "to-module" "to-error" "to-port" "to-gob" "to-event" "closure" "function" "has" "map" "task" "dt" "delta-time" "dp" "delta-profile" "speed?" "launch" "mold64" "offset?" "found?" "last?" "single?" "extend" "rejoin" "remold" "charset" "array" "replace" "reword" "move" "extract" "alter" "collect" "format" "printf" "split" "find-all" "clean-path" "input" "ask" "confirm" "list-dir" "undirize" "in-dir" "to-relative-file" "ls" "mkdir" "cd" "more" "mod" "modulo" "sign?" "minimum-of" "maximum-of" "dump-obj" "?" "help" "about" "usage" "license" "source" "what" "pending" "say-browser" "upgrade" "chat" "docs" "bugs" "changes" "why?" "demo" "load-gui" "make-banner" "funco" "t")
 (gethash 'keywords r3-highlight-symbols) (list "unset?" "none?" "logic?" "integer?" "decimal?" "percent?" "money?" "char?" "pair?" "tuple?" "time?" "date?" "binary?" "string?" "file?" "email?" "url?" "tag?" "bitset?" "image?" "vector?" "block?" "paren?" "path?" "set-path?" "get-path?" "lit-path?" "map?" "datatype?" "typeset?" "word?" "set-word?" "get-word?" "lit-word?" "refinement?" "issue?" "native?" "action?" "rebcode?" "command?" "op?" "closure?" "function?" "frame?" "object?" "module?" "error?" "task?" "port?" "gob?" "event?" "handle?" "struct?" "library?" "utype?" "add" "subtract" "multiply" "divide" "remainder" "power" "and~" "or~" "xor~" "negate" "complement" "absolute" "round" "random" "odd?" "even?" "head" "tail" "head?" "tail?" "past?" "next" "back" "skip" "at" "index?" "length?" "pick" "find" "select" "reflect" "make" "to" "copy" "take" "insert" "append" "remove" "change" "poke" "clear" "trim" "swap" "reverse" "sort" "create" "delete" "open" "close" "read" "write" "open?" "query" "modify" "update" "rename" "abs" "empty?" "rm" "native" "action" "ajoin" "also" "all" "any" "apply" "assert" "attempt" "break" "case" "catch" "comment" "compose" "continue" "do" "either" "exit" "find-script" "for" "forall" "forever" "foreach" "forskip" "halt" "if" "loop" "map-each" "quit" "protect" "unprotect" "recycle" "reduce" "repeat" "remove-each" "return" "switch" "throw" "trace" "try" "unless" "until" "while" "bind" "unbind" "bound?" "collect-words" "checksum" "compress" "decompress" "construct" "debase" "enbase" "decloak" "encloak" "deline" "enline" "detab" "entab" "delect" "difference" "exclude" "intersect" "union" "unique" "lowercase" "uppercase" "dehex" "get" "in" "parse" "set" "to-hex" "type?" "unset" "utf?" "invalid-utf?" "value?" "print" "prin" "mold" "form" "new-line" "new-line?" "to-local-file" "to-rebol-file" "transcode" "echo" "now" "wait" "wake-up" "what-dir" "change-dir" "first" "second" "third" "fourth" "fifth" "sixth" "seventh" "eighth" "ninth" "tenth" "last" "cosine" "sine" "tangent" "arccosine" "arcsine" "arctangent" "exp" "log-10" "log-2" "log-e" "not" "square-root" "shift" "++" "--" "first+" "stack" "resolve" "get-env" "set-env" "list-env" "call" "browse" "evoke" "request-file" "ascii?" "latin1?" "stats" "do-codec" "set-scheme" "load-extension" "do-commands" "ds" "dump" "check" "do-callback" "limit-usage" "selfless?" "map-event" "map-gob-offset" "as-pair" "equal?" "not-equal?" "equiv?" "not-equiv?" "strict-equal?" "strict-not-equal?" "same?" "greater?" "greater-or-equal?" "lesser?" "lesser-or-equal?" "minimum" "maximum" "negative?" "positive?" "zero?" "q" "!" "min" "max" "---" "bind?" "pwd" "+" "-" "*" "/" "//" "**" "=" "=?" "==" "!=" "<>" "!==" "<" "<=" ">" ">=" "&" "|" "and" "or" "xor"))

;;; TODO: Move to a separate module! Maybe replace with `rx-define'?
(eval-when-compile
  (defmacro defre (name re &optional str)
    `(eval-when-compile
       (push (cons ',name  (rx ,re)) rx-constituents)
       (defconst ,(intern (concat (symbol-name name) "-re"))
         (rx ,re)
         ,@(if str (list str) '())))))
(put 'defre 'lisp-indent-function 1)
(put 'defre 'doc-string-elt 3)

(defre r3-word
  (: (+ (or (syntax word) (syntax symbol)))))

(defre r3-non-delim
  (not (any ?\[ ?\] ?\{ ?\} ?\( ?\) ?\" whitespace)))

(defre r3-url
  (: symbol-start r3-word ":/" (* r3-non-delim)))

(defre r3-path
  (: "%" (* r3-non-delim)))

(defre r3-date
  (: (+ digit) (any ?\- ?\/) (+ alnum) (any ?\- ?\/) (+ digit)))

(defre r3-time
  (: (+ digit) ":" (+ digit) (? ":" (+ digit)) (? "." (+ digit))))

(defre r3-email
  (: (+ r3-non-delim) "@" (+ r3-non-delim)))

(defun r3-highlight-regex (key)
  (rx-to-string `(: symbol-start (regexp ,(regexp-opt (gethash key r3-highlight-symbols))) (* "/" r3-word) symbol-end)))

(defvar r3-font-lock-keywords
  (list
   ;; Literals
   `(,(rx r3-url)   . font-lock-string-face)
   `(,(rx r3-path)  . font-lock-string-face)
   `(,(rx r3-date)  . font-lock-string-face)
   `(,(rx r3-time)  . font-lock-string-face)
   `(,(rx r3-email) . font-lock-string-face)

   ;; Function def
   `(,(rx (: (group symbol-start r3-word symbol-end) (group ":") (* whitespace) (| "does" "func" "funct" "function" (: "make" (+ whitespace) "function!"))))
     (1 '(font-lock-function-name-face underline))
     (2 'font-lock-function-name-face))

   ;; Words
   `(,(rx (: "'" symbol-start r3-word symbol-end)) . font-lock-variable-name-face) ;;; quoted word
   `(,(rx (: ":" r3-word symbol-end)) . font-lock-variable-name-face) ;;; get word
   `(,(rx (: symbol-start r3-word ":")) . font-lock-function-name-face) ;;; set word
   `(,(rx (: symbol-start r3-word "!" symbol-end)) . font-lock-type-face) ;;; type

   ;; Predefined
   `(,(r3-highlight-regex 'constants) . font-lock-constant-face)
   `(,(r3-highlight-regex 'functions) . font-lock-reference-face)
   `(,(r3-highlight-regex 'keywords)  . font-lock-keyword-face))
  "Font-lock expressions for REBOL3 mode.")

(defvar r3-help-font-lock-keywords
  (list
   '("/[^ \r\n\t]+" . font-lock-variable-name-face)
   '("[^ \r\n\t()]+[!?]" . font-lock-type-face)
   '("\\([^ \r\n\t]+\\) --" (1 'font-lock-variable-name-face prepend))
   '("^[^ \n\r\t]+:" . font-lock-function-name-face)
   '("^;;;.*?;;;" (0 'font-lock-function-name-face prepend) (0 'underline prepend))))

;; TODO: Arguments and refinements can have a docstring too
(defun r3-docstring-p (state)
  "Return non-nil if STATE is on docstring."
  (let ((startpos (nth 8 state))
        (listbeg (nth 1 state)))
    (when listbeg
      (save-excursion
        (goto-char listbeg)
        (condition-case nil
            (progn
              (backward-sexp)
              (let ((function-name (thing-at-point 'symbol)))
                (when (or (string= function-name "func")
                          (string= function-name "funct")
                          (string= function-name "function"))
                  (goto-char listbeg)
                  (forward-char 1)
                  (forward-comment (point-max))
                  (= (point) startpos))))
          (error nil))))))

(defun r3-font-lock-syntactic-face-function (state)
  "Return syntactic face given STATE."
  (if (nth 3 state)
      (if (r3-docstring-p state)
          font-lock-doc-face
        font-lock-string-face)
    font-lock-comment-face))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Indentation

(defun r3-indent-line ()
  (interactive)
  (let* ((indent-level
          (save-excursion
            (beginning-of-line)
            (cond ((not (re-search-backward "[]()[{}]" nil 'move))
                   0)
                  ((member (aref (match-string 0) 0) (string-to-list "[{("))
                   (+ (current-indentation) r3-indent-offset))
                  (t
                   (current-indentation))))))
    (if (save-excursion (beginning-of-line) (looking-at "[ \t]*[]})]"))
        (indent-line-to (- indent-level r3-indent-offset))
      (indent-line-to (max indent-level 0)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; The Meat

;;;###autoload
(defun run-r3 ()
  "Run an inferior REBOL 3 process."
  (interactive)
  (make-comint "rebol" r3-rebol-command)
  (with-current-buffer "*rebol*"
    (r3-repl-mode))
  (pop-to-buffer "*rebol*"))

;;;###autoload
(define-derived-mode r3-mode fundamental-mode "REBOL3"
  "Major mode for editing REBOL code."
  :group 'r3
  :syntax-table r3-mode-syntax-table
  (setq-local syntax-propertize-function r3-syntax-propertize)
  (setq-local tab-width r3-indent-offset)
  ;; Font lock
  (setq-local font-lock-defaults '(r3-font-lock-keywords
                                   nil nil nil nil
                                   (font-lock-syntactic-face-function . r3-font-lock-syntactic-face-function)))
  ;; Indent
  (setq-local indent-line-function #'r3-indent-line)
  (setq-local indent-region-function nil)
  ;; Comment
  (setq-local comment-start ";")
  (setq-local comment-start-skip ";+ *")
  (setq-local comment-use-syntax t))

(define-key r3-mode-map (kbd "C-c C-h") 'r3-help)
(define-key r3-mode-map (kbd "C-c h")   'r3-help)
(define-key r3-mode-map (kbd "C-c C-s") 'r3-source)
(define-key r3-mode-map (kbd "C-c s")   'r3-source)
(define-key r3-mode-map (kbd "C-c C-c") 'r3-send-region)

;;; Minor and "minor" modes for sub-components of r3-mode

(define-derived-mode r3-source-mode r3-mode "R3-SOURCE"
  "Major mode for editing REBOL `source` output")

(define-key r3-source-mode-map (kbd "C-x C-s")
  (lambda ()
    (interactive)
    (r3-send-region (point-min) (point-max))))

(define-derived-mode r3-repl-mode comint-mode "R3-REPL"
  "Major mode for the r3 prompt"
  (setq-local font-lock-defaults '(r3-font-lock-keywords)))

(define-derived-mode r3-help-mode fundamental-mode "R3-HELP"
  "Major mode for the r3 help window"
  (setq-local font-lock-defaults '(r3-help-font-lock-keywords)))

(define-key r3-help-mode-map (kbd "C-c C-h") 'r3-help)
(define-key r3-help-mode-map (kbd "C-c h")   'r3-help)
(define-key r3-help-mode-map (kbd "C-c C-s") 'r3-source)
(define-key r3-help-mode-map (kbd "C-c s")   'r3-source)

(provide 'r3-mode)

;;; r3-mode.el ends here
