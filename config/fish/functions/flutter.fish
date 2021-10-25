# Android
set -g -x ANDROID_HOME "$HOME/sdk/Android"
set -g -x PATH $PATH "$ANDROID_HOME/cmdline-tools/latest"
set -g -x PATH $PATH "$ANDROID_HOME/cmdline-tools/latest/bin"
set -g -x PATH $PATH "$ANDROID_HOME/platform-tools"

# Flutter
set -g -x FLUTTER_ROOT "$HOME/sdk/flutter"
set -g -x PATH $PATH "$FLUTTER_ROOT/bin"
