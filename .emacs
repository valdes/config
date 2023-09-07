
;; Added by Package.el.  This must come before configurations of
;; installed packages.  Don't delete this line.  If you don't want it,
;; just comment it out by adding a semicolon to the start of the line.
;; You may delete these explanatory comments.
;;(package-initialize)

(require 'package)
(setq package-archives '(("gnu" . "https://elpa.gnu.org/packages/")
                         ("melpa" . "http://melpa.org/packages/")))

(when (not package-archive-contents)
  (package-refresh-contents))

;my packages
(defvar myPackages
  '(;cider
    ;clojure-mode
    ;paredit-mode
    ;rainbow-delimiters-mode
    magit
    helm
    projectile
    projectile-rails
    helm-projectile
    yasnippet
    yasnippet-snippets
    zenburn-theme
    which-key
    helm-lsp
    lsp-ui
    lsp-mode
    org-journal
    org-roam
    emacsql-sqlite
    org-tree-slide
    lua-mode
    helm-mode-manager
    docker-compose-mode
    dockerfile-mode
    elm-mode
    nix-mode
    zencoding-mode
    projectile-rails
    helm-projectile
    use-package
    plantuml-mode
    git-gutter))

(mapc #'(lambda (package)
    (unless (package-installed-p package)
      (package-install package)))
      myPackages)


;; interfaz config
;; Turn off the toolbar
(tool-bar-mode -1)
;;
;; Turn off the menu bar
(menu-bar-mode -1)
;;
;; Turn off the scrollbar
(scroll-bar-mode -1)
;;
;; Zenburn theme
(load-theme 'zenburn t)
;; enable line numbers globally
(when (version<= "26.0.50" emacs-version )
  (global-display-line-numbers-mode))
;;
;; Don't show the welcome message
;;(setq inhibit-startup-screen t)
;;(setq initial-scratch-message nil)
;;
;; Shut off message buffer
(setq message-log-max nil)
(kill-buffer "*Messages*")
;; Show column number in modeline
(setq column-number-mode t)
;; Modeline setup
;;   - somewhat cleaner than default
(setq default-mode-line-format
      '("-"
       mode-line-mule-info
       mode-line-modified
       mode-line-frame-identification
       mode-line-buffer-identification
       "  "
       global-mode-string
       "   %[(" mode-name mode-line-process minor-mode-alist "%n"")%]--"
       (line-number-mode "L%l--")
       (column-number-mode "C%c--")
       (-3 . "%p")
       "-%-")
)
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
;;
;; Change backup behavior to save in a specified directory
(setq backup-directory-alist '(("." . "~/.emacs.d/saves/"))
 backup-by-copying      t
 version-control        t
 delete-old-versions    t
 kept-new-versions      6
 kept-old-versions      2
)

;; Keep bookmarks in the load path
(setq bookmark-default-file "~/.emacs.d/emacs-bookmarks")

;; Keep abbreviations in the load path
(setq abbrev-file-name "~/.emacs.d/emacs-abbrev-defs")


;; Default major mode
(setq default-major-mode 'text-mode)
;;
;; Wrap lines at 70 in text-mode
(add-hook 'text-mode-hook 'turn-on-auto-fill)
;;
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

;; Accelerate the cursor when scrolling
(load "accel" t t)
;;
;; Start scrolling when 2 lines from top/bottom
(setq scroll-margin 2)
;;
;; Fix the scrolling on jumps between windows
(setq scroll-conservatively 5)

;; Cursor in same relative row and column during PgUP/DN
(setq scroll-preserve-screen-position t)


;; Always paste at the cursor
(setq mouse-yank-at-point t)

;; Kill (and paste) text from read-only buffers
(setq kill-read-only-ok 1)

;; Partially integrate the kill-ring and X cut-buffer
;(setq x-select-enable-clipboard t)

;; Copy/paste with accentuation intact
(setq selection-coding-system 'compound-text-with-extensions)

;; Delete selection on a key press
(delete-selection-mode t)
;}}}
;}}}

;{{{ Settings for various modes
;    - major modes for editing code and other formats are defined below
;
;; Auto Compression
;;   - edit files in compressed archives
(auto-compression-mode 1)
;}}}

;; globals tools
;;Start server
(server-mode 1)
;;

;; global helm
(helm-mode 1)
(global-set-key (kbd "C-x C-f") 'helm-find-files)
;; enable projectile
(projectile-mode)
;; (setq helm-projectile-fuzzy-match nil)
(require 'helm-projectile)
(helm-projectile-on)
;; rails projecctile
(projectile-rails-global-mode)
;disable temporary gitgutter (global-git-gutter-mode +1)
(global-set-key (kbd "C-x g") 'magit-status)

;; develop
;; python
;;(elpy-enable)
;;(elpy-use-ipython)
;; use flycheck not flymake with elpy
;;(when (require 'flycheck nil t)
;;  (setq elpy-modules (delq 'elpy-module-flymake elpy-modules))
;;  (add-hook 'elpy-mode-hook 'flycheck-mode))
;; enable autopep8 formatting on save
;;(require 'py-autopep8)
;;(add-hook 'elpy-mode-hook 'py-autopep8-enable-on-save)



;{{{ Custom functions

;{{{ Reload or edit .emacs on the fly
;    - key bindings defined below
;
(defun aic-reload-dot-emacs ()
  "Reload user configuration from .emacs"
  (interactive)
  ;; Fails on killing the Messages buffer, workaround:
  (get-buffer-create "*Messages*")
  (load-file "~/.emacs")
)
(defun aic-edit-dot-emacs ()
  "Edit user configuration in .emacs"
  (interactive)
  (find-file "~/.emacs")
)
;}}}

;{{{ Timestamp function, for public dotfiles
;    - date-stamp is more appropriate for txt files
;
(defun aic-dotfile-stamp ()
  "Insert time stamp at point."
  (interactive)
  (insert "Updated on: " (format-time-string "%b %e, %H:%M:%S %Z %Y" nil nil))
)
(defun aic-txtfile-stamp ()
  "Insert date at point."
  (interactive)
  (insert (format-time-string "%d.%m.%Y %H:%M"))
)
;}}}

;{{{ Quick acces to coding functions
;    - I deal with utf8, latin-2 and cp1250
;
(defun aic-recode-buffer ()
  "Define the coding system for a file."
  (interactive)
  (call-interactively 'set-buffer-file-coding-system)
)
(defun aic-encode-buffer ()
  "Revisit the buffer with another coding system."
  (interactive)
  (call-interactively 'revert-buffer-with-coding-system)
)
;}}}

;{{{ Kill all buffers except scratch
;
(defun aic-nuke-all-buffers ()
  "Kill all buffers, leaving *scratch* only."
  (interactive)
  (mapcar (lambda (x) (kill-buffer x)) (buffer-list))
  (delete-other-windows)
)
;}}}

;{{{ Quick access to OrgMode and the OrgMode agenda
;    - org-mode configuration defined below
;
(defun aic-org-index ()
   "Show the main org file."
   (interactive)
   (find-file "~/Dropbox/.org/index.org")
)
(defun aic-org-agenda ()
  "Show the org-mode agenda."
  (interactive)
  (call-interactively 'org-agenda-list)
)
;}}}

;{{{ Alias some custom functions
;
(defalias 'stamp         'aic-dotfile-stamp)
(defalias 'date-stamp    'aic-txtfile-stamp)
(defalias 'recode-buffer 'aic-recode-buffer)
(defalias 'encode-buffer 'aic-encode-buffer)
(defalias 'nuke          'aic-nuke-all-buffers)
(defalias 'org           'aic-org-index)
;}}}

;{{{ Shortcut a few commonly used functions
;
(defalias 'cr            'comment-region)
(defalias 'ucr           'uncomment-region)
(defalias 'eb            'eval-buffer)
(defalias 'er            'eval-region)
(defalias 'ee            'eval-expression)
;}}}
;}}}


;{{{ Key bindings
;    - with switched Caps_Lock and Control_L keys system wide

;{{{ Main bindings
;
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
(global-set-key [C-prior] (lambda () (interactive) (goto-char (point-min))))
(global-set-key [C-next]  (lambda () (interactive) (goto-char (point-max))))

;; Require C-x C-c prompt, no accidental quits
(global-set-key [(control x) (control c)] 
  (function 
   (lambda () (interactive) 
     (cond ((y-or-n-p "Quit? ")
       (save-buffers-kill-emacs)))))
)
;}}}

;{{{ Fn bindings
;
(global-set-key  [f1]  (lambda () (interactive) (manual-entry (current-word))))
(global-set-key  [f2]  (lambda () (interactive) (find-file "~/Dropbox/.org/notes.org")))
(global-set-key  [f3]  'aic-org-agenda)           ; Function defined previously
;(global-set-key  [f4]  'aic-visit-ansi-term)      ; Function defined previously
;(global-set-key [f5]  'aic-fold-toggle-fold)     ; Todo: Toggle all folds
;(global-set-key  [f6]  'linum-mode)               ; Toggle line numbering
(global-set-key  [f7]  'htmlfontify-buffer)
(global-set-key  [f8]  'ispell-buffer)
(global-set-key  [f9]  'ispell-change-dictionary) ; Switching 'en_US' and 'hr' often
;(global-set-key [f10]                            ; Quick menu by default
;(global-set-key  [f11] 'speedbar)
(global-set-key  [f12] 'kill-buffer)
;}}}
;}}}

;{{{ OrgMode
;; Settings
(setq org-directory "~/Dropbox/.org/")
(setq org-default-notes-file (concat org-directory "/notes.org"))
(setq org-log-done 'time)

;; Files that are included in org-mode agenda
(setq org-agenda-files
 (list "~/Dropbox/.org/index.org" "~/Dropbox/.org/personal.org" "~/Dropbox/.org/computers.org")
)
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
         ;; Dailies
         ("C-c n j" . org-roam-dailies-capture-today))
;  :bind-keymap
;	 ("C-c n d" . org-roam-dailies-map)
  :config
  (org-roam-db-autosync-mode)
  ;; If using org-roam-protocol
  (require 'org-roam-protocol))
;}}}

;{{{ OrgCapture
;; Remember frames
;;   - $ emacsclient -e '(make-remember-frame)'
;; Automatic closing of remember frames
(defadvice org-capture-finalize (after my-delete-capture-frame activate)
  "Delete the frame after `capture-finalize'."
  (when (frame-parameter nil 'my-org-capture)
    (delete-frame)))

(defadvice org-capture-destroy (after my-delete-capture-frame activate)
  "Delete the frame after `capture-destroy'."
  (when (frame-parameter nil 'my-org-capture)
    (delete-frame)))

;; Org-remember splits windows, force it to a single window
;; Initialization of remember frames
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
  :custom
  (org-image-actual-width nil))

;; sudo dired
(require 'tramp)
(defun sudired ()
  (interactive)
  (dired "/sudo::/"))

;; enable paredit-mode,rainbow in clojure-mode
(add-hook 'clojure-mode-hook #'paredit-mode)
(add-hook 'clojure-mode-hook #'rainbow-delimiters-mode)

;; show key binding help
(which-key-mode)


;; Org Journal
(require 'org-journal)
(setq org-journal-dir "~/Dropbox/.org/journal/")

;; active Babel languages
(org-babel-do-load-languages
'org-babel-load-languages
'((shell . t)
  (plantuml . t)))

;; Setup latex exporting
;;
;;

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

(setq org-plantuml-jar-path (expand-file-name "/home/vals/bin/plantuml-1.2023.10.jar"))
(add-to-list 'org-src-lang-modes '("plantuml" . plantuml))
