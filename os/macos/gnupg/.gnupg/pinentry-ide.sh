#!/bin/sh
if [ -n "$PINENTRY_USER_DATA" ]; then
  case "$PINENTRY_USER_DATA" in
    IJ_PINENTRY=*)
      "/Applications/PyCharm CE.app/Contents/jbr/Contents/Home/bin/java" -cp "/Applications/PyCharm CE.app/Contents/plugins/vcs-git/lib/git4idea-rt.jar:/Applications/PyCharm CE.app/Contents/lib/externalProcess-rt.jar" git4idea.gpg.PinentryApp
      exit $?
    ;;
  esac
fi
exec /opt/homebrew/bin/pinentry-mac "$@"