#!/usr/bin/env bash
#
# Usage: make_backport.bash <version> <texlive-installer-repo> [<branch>]
#
# Regenerate share/texlive-install-backports/<version>/ from the backport
# branch (default: backport/<version>-parallel) of a texlive-installer git
# repository. The root commit of the branch must hold the vanilla files of
# the frozen release, and the following commits the backported changes.
#
set -euo pipefail
cd "$(dirname "$0")/"

version="$1"
repo="$2"
branch="${3:-backport/${version}-parallel}"

definition="share/texlive-install/${version}"
deploy_dir="$(pwd)/share/texlive-install-backports/${version}"

# the tlnet repository of the definition: install_texlive "<version>" "<tlnet>" ...
tlnet="$(sed -n 's/^install_texlive "[^"]*" "\([^"]*\)".*/\1/p' "$definition")"
[ -n "$tlnet" ] || { echo "no tlnet in ${definition}" >&2; exit 1; }

base="$(git -C "$repo" rev-list --max-parents=0 "$branch")"
tip="$(git -C "$repo" rev-parse "$branch")"

work="$(mktemp -d "${TMPDIR:-/tmp}/make_backport.XXXXXX")"
trap 'rm -rf "$work"' EXIT

## vanilla files as distributed: the installer and the containers whose
## files are installed into TEXDIR
mkdir -p "$work/tarball" "$work/containers" "$work/tip"
curl --fail -sSL -o "$work/install-tl-unx.tar.gz" "${tlnet}install-tl-unx.tar.gz"
tar -xzf "$work/install-tl-unx.tar.gz" -C "$work/tarball"
tarball_dir="$(echo "$work"/tarball/install-tl-*)"
git -C "$repo" archive "$tip" | tar -xf - -C "$work/tip"

## the packages that install the files of the backport branch, e.g.
## texlive.infra and texlive-scripts (tetex for fmtutil.pl up to TL2018)
curl --fail -sSL -o "$work/texlive.tlpdb.xz" "${tlnet}tlpkg/texlive.tlpdb.xz"
xz -dc "$work/texlive.tlpdb.xz" >"$work/texlive.tlpdb"
(cd "$work/tip" && find . -type f | sed 's,^\./,,') >"$work/tipfiles"
containers="$(awk -v list="$work/tipfiles" '
  BEGIN { while ((getline f <list) > 0) want[f] = 1 }
  /^name / { name = $2 }
  /^ / { sub(/^ +/, ""); if (($1 in want) && name !~ /^00texlive/) print name }
' "$work/texlive.tlpdb" | sort -u)"
for container in $containers; do
  curl --fail -sSL -o "$work/${container}.tar.xz" "${tlnet}archive/${container}.tar.xz"
  tar -xJf "$work/${container}.tar.xz" -C "$work/containers"
done

rm -rf "$deploy_dir"
mkdir -p "$deploy_dir"
: >"$deploy_dir/FILES.installer"
: >"$deploy_dir/FILES.prefix"
: >"$work/sums"

git -C "$repo" diff --name-only "$base" "$tip" | sort | while read -r file; do
  mkdir -p "$deploy_dir/$(dirname "$file")"
  cp -p "$work/tip/$file" "$deploy_dir/$file"

  if [ -f "$tarball_dir/$file" ]; then
    # the root commit has to be the vanilla installer
    git -C "$repo" show "$base:$file" | cmp -s - "$tarball_dir/$file" ||
      { echo "$file: root commit of $branch differs from install-tl-unx.tar.gz" >&2; exit 1; }
    echo "$file" >>"$deploy_dir/FILES.installer"
    echo "$(shasum -a 512 <"$tarball_dir/$file" | cut -f1 -d" ")  $file" >>"$work/sums"
  fi
  if [ -f "$work/containers/$file" ]; then
    echo "$file" >>"$deploy_dir/FILES.prefix"
    echo "$(shasum -a 512 <"$work/containers/$file" | cut -f1 -d" ")  $file" >>"$work/sums"
  fi
done

## The installed TeX Live gets the modules of texlive.infra, which may be
## older than those of install-tl-unx.tar.gz the backport is based on (e.g.
## TL2024). Install the unchanged installer modules too, so that tlmgr runs
## with the same set of modules as install-tl.
(cd "$work/tip" && find tlpkg/TeXLive texmf-dist/scripts/texlive -type f) | sort | while read -r file; do
  grep -qxF "$file" "$deploy_dir/FILES.prefix" && continue
  [ -f "$work/containers/$file" ] || continue
  cmp -s "$work/tip/$file" "$work/containers/$file" && continue
  mkdir -p "$deploy_dir/$(dirname "$file")"
  cp -p "$work/tip/$file" "$deploy_dir/$file"
  echo "$file" >>"$deploy_dir/FILES.prefix"
  echo "$(shasum -a 512 <"$work/containers/$file" | cut -f1 -d" ")  $file" >>"$work/sums"
done
sort -u "$work/sums" -o "$deploy_dir/SHA512SUMS.orig"

## what install-tl itself passes to fmtutil-sys, e.g.
##   "fmtutil-sys $common_fmtutil_args --no-strict --all"
perl -I"$work/tip/tlpkg" -MTeXLive::TLConfig -e '
  local $/; my $src = <>;
  my $common = "";
  $common = eval $1 if ($src =~ /our \$common_fmtutil_args\s*=\s*(.*?);/s);
  $src =~ /"fmtutil-sys (.*?--all)"/ or die "fmtutil-sys call not found\n";
  (my $args = $1) =~ s/\$common_fmtutil_args/$common/;
  print "$args\n";
' "$work/tip/install-tl" >"$deploy_dir/FMTUTIL_ARGS"

{
  echo "repository: texlive-installer"
  echo "branch:     ${branch}"
  echo "base:       ${base}"
  echo "tip:        ${tip}"
  echo "tlnet:      ${tlnet}"
  echo
  echo "upstream commits:"
  git -C "$repo" rev-list --reverse "${base}..${tip}" | while read -r commit; do
    rev="$(git -C "$repo" show -s --format=%B "$commit" |
           sed -n 's#^git-svn-id: [^@]*@\([0-9]*\) .*#r\1#p')"
    echo "  ${rev:-local} $(git -C "$repo" show -s --format=%s "$commit")"
  done
} >"$deploy_dir/SOURCE"

ls -lR "$deploy_dir"
