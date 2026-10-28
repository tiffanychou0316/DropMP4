# Third-party components

DropMP4 application source is MIT licensed. Dependencies retain their own licenses.

| Component | License / source |
| --- | --- |
| CPython 3.12 | PSF License; https://github.com/python/cpython/tree/3.12 |
| Tcl/Tk 8.6 | Tcl/Tk license; https://www.tcl.tk/software/tcltk/license.html |
| cryptography 46.0.3 | Apache-2.0 OR BSD-3-Clause; https://github.com/pyca/cryptography/tree/46.0.3 |
| OpenSSL (linked into cryptography wheel) | Apache-2.0 (OpenSSL 3); https://openssl-library.org/source/ |
| cffi | MIT; https://foss.heptapod.net/pypy/cffi |
| pycparser | BSD-3-Clause; https://github.com/eliben/pycparser |
| python-zeroconf 0.148.0 | LGPL-2.1-or-later; https://github.com/python-zeroconf/python-zeroconf/tree/0.148.0 |
| ifaddr 0.2.0 | MIT; https://github.com/ifaddr/ifaddr/tree/0.2.0 |
| PyInstaller bootloader | GPL-2.0-or-later with distribution exception; https://pyinstaller.org/en/stable/license.html |

Windows portable distribution contains unmodified dependency binaries and available license notices under `licenses/` and `_internal/`. The exact unmodified Zeroconf 0.148.0 source archive is included in `third-party-source/`. Zeroconf remains a separate dynamically loaded module (`_internal/zeroconf`); users may replace it with a compatible build of the upstream source. Do not restrict reverse engineering needed to debug modifications to LGPL components. Build steps and dependency versions are included in the source project. Public distribution should retain these notices and accompany the portable binary with the corresponding DropMP4 source project.
