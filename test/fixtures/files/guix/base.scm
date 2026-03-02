;;; GNU Guix --- Functional package management for GNU
;;; Copyright (C) 2012-2024 Ludovic Courtes <ludo@gnu.org>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.

(define-module (gnu packages base)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix build-system gnu)
  #:use-module ((guix licenses) #:prefix license:))

;;; Commentary:
;;;
;;; Base packages of the Guix-based GNU user-land software distribution.

;; Some unrelated code to skip past
(define something-else
  (let ((x 42))
    (+ x 1)))

(define-public hello
  (package
    (name "hello")
    (version "2.12.1")
    (source (origin
              (method url-fetch)
              (uri (string-append "mirror://gnu/hello/hello-" version
                                  ".tar.gz"))
              (sha256
               (base32
                "086vqwk2wl8zfs47sq2xpjc9k066ilmb8z6dn0q6ymwjzlm196cd"))))
    (build-system gnu-build-system)
    (synopsis "Hello, GNU world: An example GNU package")
    (description
     "GNU Hello prints the message \"Hello, world!\" and then exits.  It
serves as an example of standard GNU coding practices.")
    (home-page "https://www.gnu.org/software/hello/")
    (license license:gpl3+)))

(define-public grep
  (package
    (name "grep")
    (version "3.11")
    (source (origin
              (method url-fetch)
              (uri (string-append "mirror://gnu/grep/grep-"
                                  version ".tar.xz"))
              (sha256
               (base32
                "1avf4x8skxbqrjp5j2qr9sp5vlf8jkw2i5bdn51fl3cxx3fsxchx"))))
    (build-system gnu-build-system)
    (native-inputs (list perl))
    (inputs (list pcre2))
    (synopsis "Print lines matching a pattern")
    (description
     "grep is a tool for finding text inside files.  Text is found by
matching a pattern provided by the user in one or many files.")
    (license license:gpl3+)
    (home-page "https://www.gnu.org/software/grep/")))

(define-public dual-licensed-example
  (package
    (name "dual-licensed-example")
    (version "1.0")
    (source (origin
              (method url-fetch)
              (uri "https://example.org/dual-1.0.tar.gz")
              (sha256
               (base32
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (inputs (list glib zlib))
    (native-inputs (list pkg-config))
    (propagated-inputs (list libxml2))
    (synopsis "Example package with dual license")
    (description "A fake package to test multiple license parsing.")
    (home-page "https://example.org")
    (license (list license:expat license:asl2.0))))
