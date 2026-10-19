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
for container in texlive.infra texlive-scripts; do
  curl --fail -sSL -o "$work/${container}.tar.xz" "${tlnet}archive/${container}.tar.xz"
  tar -xJf "$work/${container}.tar.xz" -C "$work/containers"
done

git -C "$repo" archive "$tip" | tar -xf - -C "$work/tip"

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
