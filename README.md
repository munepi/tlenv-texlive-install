# tlenv-texlive-install
tlenv plugin: TeX Live installation

## Backports for the frozen TeX Live releases

TeX Live 2026 can download the containers in parallel (prefetch, with
aria2c, curl or wget) and build the formats in parallel (`fmtutil
--parallel`). For the frozen releases listed under
`share/texlive-install-backports/`, `texlive-install` replaces `install-tl`,
`tlmgr.pl`, `fmtutil.pl` and their `TeXLive::*` modules with backported
versions, so that both the installation and later `tlmgr install/update` runs
use these features.

The replacement files come from the `backport/<version>-parallel` branches of
a texlive-installer git repository and are regenerated with

    ./make_backport.bash <version> <texlive-installer-repo>

Each `share/texlive-install-backports/<version>/SOURCE` names the upstream
revisions. The files are replaced only if they match the vanilla files of
the release (`SHA512SUMS.orig`); set `TEXLIVE_INSTALL_NO_BACKPORT=1` to use
the vanilla files anyway. The backported files are part of TeX Live and are
distributed under their own licenses (see `LICENSE.TL` of TeX Live).
