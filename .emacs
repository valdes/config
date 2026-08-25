
;; Added by Package.el.  This must come before configurations of
;; installed packages.  Don't delete this line.  If you don't want it,
;; just comment it out by adding a semicolon to the start of the line.
;; You may delete these explanatory comments.
;;(package-initialize)

(require 'package)
(require 'subr-x)
(setq package-archives '(("gnu" . "https://elpa.gnu.org/packages/")
                         ("melpa" . "https://melpa.org/packages/")))

;; Basic UI defaults
;; Turn off the toolbar
(tool-bar-mode -1)

;; Turn off the menu bar
(menu-bar-mode -1)

;; Turn off the scrollbar
(scroll-bar-mode -1)

;; enable line numbers globally
(global-display-line-numbers-mode 1)

;; Show column number in modeline
(setq column-number-mode t)

;; Answer y or n instead of yes or no at prompts
(defalias 'yes-or-no-p 'y-or-n-p)

;{{{ General settings
;
;; Provide an error trace if loading .emacs fails
(setq debug-on-error t)

;; Encoding
(prefer-coding-system 'utf-8)
(set-language-environment 'utf-8)
(setq locale-coding-system 'utf-8)
(set-terminal-coding-system 'utf-8)
(set-keyboard-coding-system 'utf-8)
(set-selection-coding-system 'utf-8)

;; Spell checking
(setq-default ispell-program-name "aspell"
  ispell-extra-args '("--sug-mode=ultra"))
(setq-default ispell-dictionary "en_US")

;; Default Web Browser
(setq browse-url-browser-function 'browse-url-firefox)

;; Show unfinished keystrokes early
(setq echo-keystrokes 0.1)

;; Ignore case on completion
(setq completion-ignore-case t
  read-file-name-completion-ignore-case t)


;; Save after a certain amount of time.
(setq auto-save-timeout 1800)

;; Keep backups under ~/.emacs.d instead of scattering ~ files everywhere.
(setq backup-directory-alist '(("." . "~/.emacs.d/saves/"))
      backup-by-copying t
      version-control t
      delete-old-versions t
      kept-new-versions 6
      kept-old-versions 2)

;; Keep bookmarks in the load path
(setq bookmark-default-file "~/.emacs.d/emacs-bookmarks")

;; Keep abbreviations in the load path
(setq abbrev-file-name "~/.emacs.d/emacs-abbrev-defs")


;; Default major mode
(setq default-major-mode 'text-mode)
;; Wrap lines at 70 in text-mode
(add-hook 'text-mode-hook 'turn-on-auto-fill)

;; Text files end in new lines.
(setq require-final-newline t)

;; Narrowing enabled
(put 'narrow-to-region 'disabled nil)

;{{{ Mouse and cursor settings
;
;; Enable mouse scrolling
(mouse-wheel-mode t)

;; Push the mouse out of the way on cursor approach
(mouse-avoidance-mode 'jump)

;; Stop cursor from blinking
(blink-cursor-mode nil)

;; Load optional cursor acceleration support when available.
(load "accel" t t)

;; Start scrolling when 2 lines from top/bottom
(setq scroll-margin 2)

;; Fix the scrolling on jumps between windows
(setq scroll-conservatively 5)

;; Cursor in same relative row and column during PgUP/DN
(setq scroll-preserve-screen-position t)


;; Always paste at the cursor
(setq mouse-yank-at-point t)

;; Kill (and paste) text from read-only buffers
(setq kill-read-only-ok 1)

;; Copy/paste with accentuation intact
(setq selection-coding-system 'compound-text-with-extensions)

;; Delete selection on a key press
(delete-selection-mode t)
;}}}
;}}}

;{{{ Built-in editing behavior
;    - core behavior provided by Emacs itself
;
;; Auto Compression
;;   - edit files in compressed archives
(auto-compression-mode 1)
;}}}

;; Global tools
;; Start the server for emacsclient.
(server-mode 1)
(recentf-mode 1)
(repeat-mode 1)
(winner-mode 1)
(electric-pair-mode 1)
(global-auto-revert-mode 1)

;; Completion and project navigation
(define-prefix-command 'aic-project-map)
(global-set-key (kbd "C-c p") 'aic-project-map)
(define-prefix-command 'aic-git-map)
(global-set-key (kbd "C-c g") 'aic-git-map)

(use-package savehist
  :ensure nil
  :init (savehist-mode 1))

(use-package vertico
  :ensure t
  :init (vertico-mode 1))

(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion)))))

(use-package marginalia
  :ensure t
  :init (marginalia-mode 1))

(use-package consult
  :ensure t
  :init
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)
  :bind (([f10] . consult-buffer)
         ([S-f10] . consult-recent-file)
         ("C-c p b" . consult-project-buffer)
         ("C-c p r" . consult-ripgrep)))

(use-package embark
  :ensure t
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)))

(use-package embark-consult
  :ensure t
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

(use-package corfu
  :ensure t
  :custom
  (corfu-auto t)
  (corfu-auto-delay 0.15)
  (corfu-auto-prefix 2)
  (corfu-cycle t)
  (corfu-preselect 'prompt)
  :init
  (global-corfu-mode 1))

(use-package cape
  :ensure t
  :init
  (add-to-list 'completion-at-point-functions #'cape-file))

(use-package project
  :ensure nil
  :custom
  (project-switch-commands
   '((project-find-file "Find file")
     (consult-project-buffer "Buffer")
     (project-dired "Dired")
     (consult-ripgrep "Ripgrep"))))

(global-set-key (kbd "C-c p f") #'project-find-file)
(global-set-key (kbd "C-c p p") #'project-switch-project)
(global-set-key (kbd "C-c p k") #'project-kill-buffers)
(global-set-key (kbd "C-c p t") #'aic-project-test)
(global-set-key (kbd "C-c p d") #'aic-project-difftastic)
(global-set-key (kbd "C-c p D") #'aic-project-difftastic-base)
(global-set-key (kbd "C-c p M") #'aic-project-run-make-target)

(use-package magit
  :ensure t
  :custom
  (magit-diff-refine-hunk 'all)
  :bind ("C-x g" . magit-status))

(with-eval-after-load 'compile
  (require 'ansi-color)
  (setq compilation-auto-jump-to-first-error t
        compilation-scroll-output 'first-error)
  (add-hook 'compilation-filter-hook #'ansi-color-compilation-filter))

;{{{ Custom functions

;{{{ Reload or edit .emacs on the fly
;    - key bindings defined below
;
(defun aic-reload-dot-emacs ()
  "Reload user configuration from .emacs"
  (interactive)
  (load-file "~/.emacs"))

(defun aic-edit-dot-emacs ()
  "Edit user configuration in .emacs"
  (interactive)
  (find-file "~/.emacs"))
;}}}

;{{{ Timestamp function, for public dotfiles
;    - date-stamp is more appropriate for txt files
;
(defun aic-dotfile-stamp ()
  "Insert time stamp at point."
  (interactive)
  (insert "Updated on: " (format-time-string "%b %e, %H:%M:%S %Z %Y" nil nil)))

(defun aic-txtfile-stamp ()
  "Insert date at point."
  (interactive)
  (insert (format-time-string "%d.%m.%Y %H:%M")))
;}}}

;{{{ Quick access to coding functions
;    - I deal with utf8, latin-2 and cp1250
;
(defun aic-recode-buffer ()
  "Define the coding system for a file."
  (interactive)
  (call-interactively 'set-buffer-file-coding-system))

(defun aic-encode-buffer ()
  "Revisit the buffer with another coding system."
  (interactive)
  (call-interactively 'revert-buffer-with-coding-system))
;}}}

;{{{ Kill all buffers except scratch
;
(defun aic-nuke-all-buffers ()
  "Kill all buffers, leaving *scratch* only."
  (interactive)
  (mapcar (lambda (x) (kill-buffer x)) (buffer-list))
  (delete-other-windows))
;}}}

;{{{ Quick access to Org mode files and agenda
;    - convenience wrappers around built-in Org commands
;
(defun aic-org-index ()
  "Show the main org file."
  (interactive)
  (find-file "~/Dropbox/.org/index.org"))

(defun aic-org-agenda ()
  "Show the org-mode agenda."
  (interactive)
  (call-interactively 'org-agenda-list))
;}}}

;{{{ Short aliases for interactive use
;    - keep old convenience names while the implementation stays explicit
;
(defalias 'stamp         'aic-dotfile-stamp)
(defalias 'date-stamp    'aic-txtfile-stamp)
(defalias 'recode-buffer 'aic-recode-buffer)
(defalias 'encode-buffer 'aic-encode-buffer)
(defalias 'nuke          'aic-nuke-all-buffers)
(defalias 'org           'aic-org-index)
(defalias 'cr            'comment-region)
(defalias 'ucr           'uncomment-region)
(defalias 'eb            'eval-buffer)
(defalias 'er            'eval-region)
(defalias 'ee            'eval-expression)
;}}}

;{{{ Named helpers for key bindings
;    - use named commands instead of inline lambdas to keep bindings readable
;
(defun aic-goto-buffer-start ()
  "Jump to the beginning of the buffer."
  (interactive)
  (goto-char (point-min)))

(defun aic-goto-buffer-end ()
  "Jump to the end of the buffer."
  (interactive)
  (goto-char (point-max)))

(defun aic-kill-emacs-confirm ()
  "Quit Emacs after confirmation."
  (interactive)
  (when (y-or-n-p "Quit? ")
    (save-buffers-kill-emacs)))

(defun aic-manual-current-word ()
  "Open the manual entry for the symbol at point."
  (interactive)
  (manual-entry (current-word)))

(defun aic-open-org-notes ()
  "Open the default Org notes file."
  (interactive)
  (find-file "~/Dropbox/.org/notes.org"))
;}}}


;{{{ Key bindings
;    - with switched Caps_Lock and Control_L keys system wide

;{{{ Main bindings
;; C-w to backward kill for compatibility (and ease of use)
(global-set-key "\C-w"     'backward-kill-word)
;; ...and then provide alternative for cutting
(global-set-key "\C-x\C-k" 'kill-region)

;; Change C-x C-b behavior (buffer management)
(global-set-key "\C-x\C-b" 'electric-buffer-list)

;; Reload or edit .emacs as defined above
(global-set-key "\C-c\C-r" 'aic-reload-dot-emacs)
(global-set-key "\C-c\C-e" 'aic-edit-dot-emacs)

;; Toggle soft word wrapping
(global-set-key "\C-cw" 'toggle-truncate-lines)

;; Quick access to the speedbar
(global-set-key "\C-cs" 'speedbar-get-focus)

;; org-mode bindings for quick access (see below)
(global-set-key "\C-cl" 'org-store-link)
(global-set-key "\C-ca" 'org-agenda)
(global-set-key "\C-cc" 'org-capture)

;; M-w copies to Clipboard selection instead Primary
(global-set-key (kbd "M-w") 'clipboard-kill-ring-save)

;; Quicker access to go-to line
(global-set-key (kbd "M-g") 'goto-line)

;; Menu bar toggle, as in my vimperator setup
(global-set-key (kbd "<M-down>") 'menu-bar-mode)

;; Jump to the start/end of the document with C-PgUP/DN
(global-set-key [C-prior] 'aic-goto-buffer-start)
(global-set-key [C-next]  'aic-goto-buffer-end)

;; Require C-x C-c prompt, no accidental quits
(global-set-key (kbd "C-x C-c") 'aic-kill-emacs-confirm)
;}}}

;{{{ Fn bindings
(global-set-key  [f1]  'aic-manual-current-word)
(global-set-key  [f2]  'aic-open-org-notes)
(global-set-key  [f3]  'aic-org-agenda)           ; Function defined previously
(global-set-key  [f4]  'make-remember-frame)
(global-set-key  [f5]  'org-tree-slide-mode)
(global-set-key  [f6]  'display-line-numbers-mode)
(global-set-key  [f7]  'htmlfontify-buffer)
(global-set-key  [f8]  'ispell-buffer)
(global-set-key  [f9]  'ispell-change-dictionary) ; Switching 'en_US' and 'hr' often
(global-set-key [f10]  'consult-buffer)
(global-set-key [S-f10] 'consult-recent-file)
(global-set-key [f11]  'toggle-frame-maximized)
(global-set-key  [f12] 'kill-buffer)
;}}}
;}}}

;{{{ Org mode
;; Core Org settings
(setq org-directory "~/Dropbox/.org/")
(setq org-default-notes-file (concat org-directory "/notes.org"))
(setq org-log-done 'time)

;; Files included in the agenda.
(setq org-agenda-files
      (list "~/Dropbox/.org/index.org"
            "~/Dropbox/.org/personal.org"
            "~/Dropbox/.org/computers.org"))
;}}}

;{{{ Org Roam
(setq org-roam-v2-ack t)
(use-package org-roam
  :ensure t
  :custom
  (org-roam-directory (file-truename "~/Dropbox/.org-roam/"))
  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n g" . org-roam-graph)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n c" . org-roam-capture)
         ("C-c n j" . org-roam-dailies-capture-today))
  :config
  (org-roam-db-autosync-mode)
  (require 'org-roam-protocol))
;}}}

;{{{ Org capture helpers
;; Create and clean up dedicated frames for capture launched via emacsclient.
(defun aic-delete-capture-frame (&rest _)
  "Delete the frame after `capture-finalize'."
  (when (frame-parameter nil 'my-org-capture)
    (delete-frame)))

(advice-add 'org-capture-finalize :after #'aic-delete-capture-frame)
(advice-add 'org-capture-destroy :after #'aic-delete-capture-frame)

;; Force org-capture to stay in a single-purpose frame.
(defun make-remember-frame ()
  "Create a new frame and run `org-capture'."
  (interactive)
  (select-frame (make-frame '((my-org-capture . t) (width . 80) (height . 10))))
  (delete-other-windows)
  (cl-letf (((symbol-function 'switch-to-buffer-other-window) #'switch-to-buffer))
    (condition-case err
        (org-capture)
      ;; `org-capture' signals (error "Abort") when "q" is typed, so
      ;; delete the newly-created frame in this scenario.
      (error (when (equal err '(error "Abort"))
               (delete-frame))))))
;}}}

;; Org presentations
(use-package org-tree-slide
  :ensure t
  :custom
  (org-image-actual-width nil))

;; Browse files as root when needed.
(require 'tramp)
(defun sudired ()
  (interactive)
  (dired "/sudo::/"))

;; Editing helpers
(use-package paredit
  :ensure t
  :hook
  (clojure-mode . paredit-mode))
(use-package rainbow-delimiters
  :ensure t
  :hook
  (clojure-mode . rainbow-delimiters-mode))

;; Show available key bindings after a prefix key.
(use-package which-key
  :ensure t
  :config
  (which-key-mode)
  (which-key-add-key-based-replacements
    "C-c p" "project"
    "C-c g" "git"
    "C-c x" "agent"))


;; Org Journal
(use-package org-journal
  :ensure t
  :init
  (setq org-journal-dir "~/Dropbox/.org/journal/"))

;; Enable Org Babel languages used in this setup.
(org-babel-do-load-languages
 'org-babel-load-languages
 '((C . t)
   (shell . t)
   ;;(zig . t)
   (plantuml . t)))

;; LaTeX export

(unless (boundp 'org-latex-classes)
  (setq org-latex-classes nil))

(add-to-list 'org-latex-classes
             '("my-style"
               "\\documentclass{./my-style}
                 [DEFAULT-PACKAGES]
                 [PACKAGES]
                 [EXTRA]"
               ("\\section{%s}" . "\\section{%s}")
               ("\\subsection{%s}" . "\\subsection{%s}")
               ("\\subsubsection{%s}" . "\\subsubsection{%s}")
               ("\\paragraph{%s}" . "\\paragraph{%s}")
               ("\\subparagraph{%s}" . "\\subparagraph{%s}")))

(use-package plantuml-mode
  :ensure t
  :init
  (add-to-list 'org-src-lang-modes '("plantuml" . plantuml))
  :config
  (setq org-plantuml-jar-path (expand-file-name "~/plantuml-1.2023.10.jar")))

;; Use minted for syntax-highlighted PDF export.
(setq org-latex-listings 'minted
      org-latex-packages-alist '(("" "minted"))
      org-latex-pdf-process
      '("pdflatex -shell-escape -interaction nonstopmode -output-directory %o %f"
        "pdflatex -shell-escape -interaction nonstopmode -output-directory %o %f"))

(use-package doom-modeline
  :ensure t
  :hook (after-init . doom-modeline-mode))
(setq doom-modeline-enable-word-count t)

(use-package yasnippet
  :ensure t
  :config (yas-global-mode))

;; Java / Spring Boot development
(when (require 'treesit nil t)
  (add-to-list 'treesit-extra-load-path
               (expand-file-name "~/.emacs.d/tree-sitter"))
  (when (and (treesit-available-p)
             (treesit-language-available-p 'java))
    (add-to-list 'major-mode-remap-alist '(java-mode . java-ts-mode))))

(defun aic-project-root ()
  "Return the current project root or `default-directory'."
  (or (when-let ((project (project-current nil)))
        (car (project-roots project)))
      default-directory))

(defun aic-file-in-project (file)
  "Return FILE under the current project root when it exists."
  (let ((path (expand-file-name file (aic-project-root))))
    (when (file-exists-p path)
      path)))

(defun aic-project-make-targets ()
  "Return documented Makefile targets as (TARGET . DESCRIPTION) pairs."
  (when-let ((makefile (aic-file-in-project "Makefile")))
    (with-temp-buffer
      (insert-file-contents makefile)
      (let (targets)
        (goto-char (point-min))
        (while (re-search-forward
                "^\\([[:alnum:]_.-]+\\):.*##[[:space:]]*\\(.+\\)$" nil t)
          (push (cons (match-string-no-properties 1)
                      (string-trim (match-string-no-properties 2)))
                targets))
        (nreverse targets)))))

(defun aic-project-has-make-target-p (target)
  "Return non-nil when TARGET is documented by the project Makefile."
  (assoc target (aic-project-make-targets)))

(defvar aic-compilation-scope nil)

(defun aic-compilation-buffer-name (_mode)
  "Return a project and scope specific compilation buffer name."
  (format "*%s:%s*"
          (file-name-nondirectory
           (directory-file-name (expand-file-name (aic-project-root))))
          (or aic-compilation-scope "compile")))

(defun aic-compile (command scope &optional directory)
  "Run COMMAND in a scoped compilation buffer.
SCOPE identifies the result buffer.  DIRECTORY defaults to the project root."
  (let ((default-directory (or directory (aic-project-root)))
        (aic-compilation-scope scope)
        (compilation-buffer-name-function #'aic-compilation-buffer-name))
    (compile command)))

(defun aic-project-test-command ()
  "Return the conventional test command for the current project."
  (cond
   ((aic-project-has-make-target-p "test") "make test")
   ((aic-file-in-project "mvnw") "./mvnw test")
   ((aic-file-in-project "gradlew") "./gradlew test")
   ((aic-file-in-project "pom.xml") "mvn test")
   ((or (aic-file-in-project "build.gradle")
        (aic-file-in-project "build.gradle.kts")) "gradle test")
   ((aic-file-in-project "Cargo.toml") "cargo test")
   ((aic-file-in-project "build.zig") "zig build test")
   ((aic-file-in-project "Makefile") "make test")
   (t compile-command)))

(defun aic-project-test ()
  "Run the conventional test command for the current project."
  (interactive)
  (aic-compile (aic-project-test-command) "test"))

(defun aic-project-run-make-target ()
  "Select and run a documented project Makefile target."
  (interactive)
  (let ((targets (aic-project-make-targets)))
    (unless targets
      (user-error "Project Makefile has no targets documented with ##"))
    (let* ((candidates
            (mapcar (lambda (target)
                      (cons (format "%-24s %s" (car target) (cdr target))
                            (car target)))
                    targets))
           (selection (completing-read "Make target: " candidates nil t))
           (target (cdr (assoc selection candidates))))
      (aic-compile (concat "make " (shell-quote-argument target))
                   (concat "make-" target)))))

(defun aic-require-difftastic ()
  "Require the Difftastic executable."
  (unless (executable-find "difft")
    (user-error "difft is not available in PATH")))

(defun aic-project-difftastic ()
  "Review tracked project changes against HEAD with Difftastic."
  (interactive)
  (aic-require-difftastic)
  (aic-compile "git -c diff.external=difft diff --ext-diff HEAD"
               "review-head"))

(defun aic-git-output (&rest arguments)
  "Return trimmed Git output for ARGUMENTS, or nil when Git fails."
  (with-temp-buffer
    (let ((status (apply #'process-file "git" nil t nil arguments)))
      (when (zerop status)
        (let ((output (string-trim (buffer-string))))
          (unless (string-empty-p output)
            output))))))

(defun aic-git-review-upstream ()
  "Return an upstream suitable as a review base, if one exists."
  (let ((current (aic-git-output "branch" "--show-current"))
        (upstream (aic-git-output "rev-parse" "--abbrev-ref"
                                  "--symbolic-full-name" "@{upstream}")))
    (when (and upstream current
               (not (equal upstream current))
               (not (string-suffix-p (concat "/" current) upstream)))
      upstream)))

(defun aic-git-review-base ()
  "Return the most relevant base branch for reviewing the current branch."
  (let* ((current (aic-git-output "branch" "--show-current"))
         (dev-loop-target
          (and current
               (aic-git-output "config" "--get"
                               (format "branch.%s.dev-loop-target" current))))
         (automatic
          (or (and dev-loop-target
                   (not (equal dev-loop-target current))
                   dev-loop-target)
              (aic-git-review-upstream)
              (aic-git-output "symbolic-ref" "--short"
                              "refs/remotes/origin/HEAD"))))
    (or automatic
        (let* ((branches-output
                (aic-git-output "for-each-ref" "--format=%(refname:short)"
                                "refs/heads"))
               (branches (and branches-output
                              (delete current (split-string branches-output "\n" t)))))
          (unless branches
            (user-error "Repository has no alternative local branch to review against"))
          (completing-read "Review base: " branches nil t)))))

(defun aic-project-difftastic-base ()
  "Review the current branch and working tree against their merge base."
  (interactive)
  (aic-require-difftastic)
  (let* ((default-directory (aic-project-root))
         (base (aic-git-review-base))
         (merge-base (aic-git-output "merge-base" "HEAD" base)))
    (unless merge-base
      (user-error "Cannot find a merge base with %s" base))
    (aic-compile
     (format "git -c diff.external=difft diff --ext-diff %s"
             (shell-quote-argument merge-base))
     (concat "review-" base))))

(defun aic-copy-to-clipboard (text)
  "Copy TEXT to the kill ring and graphical clipboard."
  (kill-new text)
  (when (display-graphic-p)
    (gui-set-selection 'CLIPBOARD text)))

(defun aic-project-file-reference (&optional position)
  "Return the current project-relative file and POSITION as a reference."
  (unless buffer-file-name
    (user-error "Current buffer does not visit a file"))
  (format "%s:%d"
          (file-relative-name buffer-file-name (aic-project-root))
          (line-number-at-pos (or position (point)))))

(defun aic-codex-copy-file-reference ()
  "Copy the current project-relative file and line for Codex."
  (interactive)
  (let ((reference (aic-project-file-reference)))
    (aic-copy-to-clipboard reference)
    (message "Copied %s" reference)))

(defun aic-codex-copy-region (start end)
  "Copy region START to END with project-relative context for Codex."
  (interactive "r")
  (unless (use-region-p)
    (user-error "Select a region first"))
  (unless buffer-file-name
    (user-error "Current buffer does not visit a file"))
  (let* ((path (file-relative-name buffer-file-name (aic-project-root)))
         (first-line (line-number-at-pos start))
         (last-line (line-number-at-pos end))
         (context (format "Context from %s:%d-%d\n\n%s"
                          path first-line last-line
                          (buffer-substring-no-properties start end))))
    (aic-copy-to-clipboard context)
    (message "Copied %s:%d-%d" path first-line last-line)))

(defun aic-agent-task-context ()
  "Return concise context for an agent task handoff."
  (cond
   ((and (use-region-p) buffer-file-name)
    (let* ((start (region-beginning))
           (end (region-end))
           (path (file-relative-name buffer-file-name (aic-project-root)))
           (first-line (line-number-at-pos start))
           (last-line (line-number-at-pos end)))
      (format "Context from %s:%d-%d\n\n%s"
              path first-line last-line
              (buffer-substring-no-properties start end))))
   (buffer-file-name
    (aic-project-file-reference))
   (t
    "[add relevant files, errors, or command output]")))

(defvar-local aic-dev-task-root nil)

(defun aic-dev-task-cancel ()
  "Delete and close the current unsubmitted task draft."
  (interactive)
  (unless aic-dev-task-root
    (user-error "Current buffer is not a dev task"))
  (let ((file buffer-file-name))
    (set-buffer-modified-p nil)
    (when (and file (file-exists-p file))
      (delete-file file))
    (kill-buffer (current-buffer))
    (message "Task draft cancelled")))

(defun aic-dev-task-open (job)
  "Open a context-aware task contract; include ticket fields when JOB is non-nil."
  (let* ((root (directory-file-name (expand-file-name (aic-project-root))))
         (context (aic-agent-task-context))
         (project (file-name-nondirectory root))
         (directory (expand-file-name project "~/tasks/"))
         (archive (expand-file-name
                   (format "%s-%s.org" (format-time-string "%Y%m%d-%H%M%S-%N")
                           (if job "job" "personal"))
                   directory)))
    (make-directory directory t)
    (set-file-modes (expand-file-name "~/tasks/") #o700)
    (set-file-modes directory #o700)
    (find-file archive)
    (org-mode)
    (setq-local aic-dev-task-root root)
    (local-set-key [escape] #'aic-dev-task-cancel)
    (insert
     (format
      (concat "Agent: codex\n"
              "%s"
              "Title:\n\n"
              "* Outcome\n"
              "[describe the concrete result]\n\n"
              "* Context\n"
              "%s\n\n"
              "* Constraints\n"
              "- Follow the active AGENTS.md instructions.\n"
              "- [add task-specific boundaries]\n\n"
              "* Done when\n"
              "- Relevant checks pass.\n"
              "- The final diff is reviewed.\n"
              "- [add an observable acceptance criterion]\n")
      (if job "Ticket:\n" "") context))
    (save-buffer)
    (set-file-modes archive #o600)
    (goto-char (point-min))
    (message "Edit the task, submit with C-c x s, or cancel with Escape")))

(defun aic-dev-task-personal ()
  "Open a personal dev-loop task contract."
  (interactive)
  (aic-dev-task-open nil))

(defun aic-dev-task-job ()
  "Open a ticketed dev-loop task contract."
  (interactive)
  (aic-dev-task-open t))

(defun aic-dev-task-submit ()
  "Archive and submit the current task contract to dev-loop."
  (interactive)
  (unless aic-dev-task-root
    (user-error "Current buffer is not a dev task"))
  (unless (executable-find "dev-loop")
    (user-error "dev-loop is not available in PATH"))
  (save-buffer)
  (let ((default-directory (file-name-as-directory aic-dev-task-root)))
    (start-process "dev-loop" "*dev-loop*" "dev-loop"
                   "start-task" buffer-file-name))
  (set-buffer-modified-p nil)
  (kill-buffer (current-buffer))
  (message "Task submitted; see *dev-loop* for launch errors"))

(defun aic-codex-open-project-session ()
  "Open the current project's Codex tmux session in Ghostty."
  (interactive)
  (unless (executable-find "dev-session")
    (user-error "dev-session is not available in PATH"))
  (let ((root (directory-file-name (expand-file-name (aic-project-root)))))
    (start-process "dev-session" "*dev-session*"
                   "dev-session" "--launch" root)
    (message "Opening Codex session for %s" root)))

(define-prefix-command 'aic-codex-map)
(global-set-key (kbd "C-c x") 'aic-codex-map)
(define-key aic-codex-map (kbd "a") #'aic-codex-open-project-session)
(define-key aic-codex-map (kbd "f") #'aic-codex-copy-file-reference)
(define-key aic-codex-map (kbd "r") #'aic-codex-copy-region)
(define-key aic-codex-map (kbd "p") #'aic-dev-task-personal)
(define-key aic-codex-map (kbd "j") #'aic-dev-task-job)
(define-key aic-codex-map (kbd "s") #'aic-dev-task-submit)

(defun aic-eglot-mode-setup (&optional format-on-save)
  "Start Eglot and optionally enable FORMAT-ON-SAVE in the current buffer."
  (require 'eglot)
  (eglot-ensure)
  (remove-hook 'before-save-hook #'eglot-format-buffer t)
  (when format-on-save
    (add-hook 'before-save-hook #'eglot-format-buffer nil t)))

(defun aic-eglot-format-mode-setup ()
  "Start Eglot and enable Eglot formatting on save."
  (aic-eglot-mode-setup t))

(use-package gradle-mode
  :ensure t
  :hook ((java-mode . gradle-mode)
         (java-ts-mode . gradle-mode)))

(use-package groovy-mode
  :ensure t
  :mode "\\.gradle\\'")

(use-package yaml-mode
  :ensure t
  :mode (("\\.ya?ml\\'" . yaml-mode)
         ("application.*\\.ya?ml\\'" . yaml-mode)))

(use-package restclient
  :ensure t
  :mode "\\.http\\'")

;; C and C++ development
(defun aic-c-mode-setup ()
  "Set sensible defaults for C and C++ development."
  (setq-local c-basic-offset 4)
  (setq-local indent-tabs-mode nil)
  (setq-local tab-width 4)
  (unless (local-variable-p 'compile-command)
    (setq-local compile-command "make -k "))
  (aic-eglot-mode-setup t))

;; Zig development
(defun aic-zig-mode-setup ()
  "Set sensible defaults for Zig development."
  (setq-local indent-tabs-mode nil)
  (setq-local tab-width 4)
  (unless (local-variable-p 'compile-command)
    (setq-local compile-command
                (if (locate-dominating-file default-directory "build.zig")
                    "zig build"
                  (if buffer-file-name
                      (format "zig run %s"
                              (shell-quote-argument
                               (file-name-nondirectory buffer-file-name)))
                    "zig build"))))
  (aic-eglot-mode-setup t))

(use-package zig-mode
  :ensure t)

(use-package rust-mode
  :ensure t
  :mode "\\.rs\\'")

(use-package eglot
  :ensure nil
  :hook ((java-mode . aic-eglot-mode-setup)
         (java-ts-mode . aic-eglot-mode-setup)
         (c-mode . aic-c-mode-setup)
         (c-ts-mode . aic-c-mode-setup)
         (c++-mode . aic-c-mode-setup)
         (c++-ts-mode . aic-c-mode-setup)
         (zig-mode . aic-zig-mode-setup)
         (yaml-mode . aic-eglot-format-mode-setup)
         (nix-mode . aic-eglot-format-mode-setup)
         (rust-mode . aic-eglot-format-mode-setup)
         (rust-ts-mode . aic-eglot-format-mode-setup))
  :config
  (add-to-list 'eglot-server-programs
               '((java-mode java-ts-mode) . ("jdtls")))
  (add-to-list 'eglot-server-programs
               '((c-mode c-ts-mode c++-mode c++-ts-mode) . ("clangd")))
  (add-to-list 'eglot-server-programs
               '(zig-mode . ("zls")))
  (add-to-list 'eglot-server-programs
               '(yaml-mode . ("yaml-language-server" "--stdio")))
  (add-to-list 'eglot-server-programs
               '(nix-mode . ("nixd")))
  (add-to-list 'eglot-server-programs
               '((rust-mode rust-ts-mode) . ("rust-analyzer"))))

(use-package clang-format
  :ensure t)

(use-package docker-compose-mode :ensure t)
(use-package dockerfile-mode :ensure t)
(use-package nix-mode :ensure t)
(use-package git-gutter
  :ensure t
  :init
  (global-git-gutter-mode 1)
  :bind (:map aic-git-map
              ("p" . git-gutter:previous-hunk)
              ("n" . git-gutter:next-hunk)
              ("h" . git-gutter:popup-hunk)))
;; Zenburn theme
(use-package zenburn-theme
  :ensure t
  :config (load-theme 'zenburn t))
