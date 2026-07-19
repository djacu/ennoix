# --batch load gate for the flagship package. Catches STARTUP-time errors
# only; deferred :config bodies never run in --batch.
# https://github.com/djacu/ennoix/issues/4
{ runCommand, ennoix-emacs }:
runCommand "ennoix-tests-load" { } ''
  export HOME=$(mktemp -d)
  ${ennoix-emacs}/bin/emacs --batch \
    --eval '(package-activate-all)' \
    --eval '(load (locate-library "default") nil t)' \
    --eval '(message "ennoix-config-loaded-ok")' > log 2>&1 \
    || { echo "emacs exited non-zero:"; cat log; exit 1; }
  if grep -qiE 'error \(|lisp error|definition is void|wrong type|void-(function|variable)' log; then
    echo "config produced an error at load:"; cat log; exit 1
  fi
  grep -q 'ennoix-config-loaded-ok' log || { echo "missing success marker:"; cat log; exit 1; }
  touch $out
''
