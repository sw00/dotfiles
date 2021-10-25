function sdk
  bash -c '. ~/.sdkman/bin/sdkman-init.sh; sdk "$@"' sdk $argv
end

set PATH $PATH (find ~/.sdkman/candidates/*/current/bin -maxdepth 0)

set -g -x SDKMAN_DIR "$HOME/.sdkman"
set -g -x JAVA_HOME "$SDKMAN_DIR/candidates/java/current"
set -g -x PATH $PATH "$JAVA_HOME/bin"

# Android, Flutter Stack:
set -g -x ANDROID_HOME "$HOME/sdk/Android"
set -g -x PATH $PATH "$ANDROID_HOME/cmdline-tools/latest"
set -g -x PATH $PATH "$ANDROID_HOME/cmdline-tools/latest/bin"
set -g -x PATH $PATH "$ANDROID_HOME/platform-tools"

