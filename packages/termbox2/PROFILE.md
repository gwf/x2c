# termbox2 2.5.0 profile

- Upstream release: `v2.5.0`
- Source archive:
  `https://github.com/termbox/termbox2/archive/refs/tags/v2.5.0.tar.gz`
- Source archive SHA-256:
  `1d7a9811060e3673be417019007acbf4e2575734b6f95baaf6e8aed27f06c65a`
- `termbox2.h` SHA-256:
  `ef63b6bd6e3a1c8ad339b7aa0bf52dc21f3e92bd886264ebe588ab86ccd1e5d1`
- Profile: `TB_LIB_OPTS`, which selects `TB_OPT_ATTR_W=64` and
  `TB_OPT_EGC`; the single header is instantiated once by `src/termbox2.c`.
- Linked dependencies: the platform C/POSIX runtime only. At runtime termbox
  reads the host's terminfo database and uses tty, termios, ioctl, select,
  pipe, and signal facilities.
- Vendored source and local patches: none. The prepared real upstream header
  is included through `src/termbox2-2.5.h`.
- Release root `LICENSE` SHA-256:
  `de32c2a6efe313c76fb56692a54a8b544ed31cc9ca04a052e134844740a0bb1e`;
  reproduced in `LICENSES/termbox2-release-LICENSE.txt`.
- Header-embedded MIT notice SHA-256 after removing the surrounding C comment
  delimiters:
  `23190431e232877cc40c6d39af50c58719402c4a76404e41b73358a08ef405fa`;
  reproduced in `LICENSES/termbox2-header-MIT.txt`.

`dependency.json` is the machine-readable source record. `make
verify-profile` checks the admitted header and both exact notices.
