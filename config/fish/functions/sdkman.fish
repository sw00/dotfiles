function sdk
  bash -c '. ~/.sdkman/bin/sdkman-init.sh; sdk "$@"' sdk $argv
end

set PATH $PATH (find ~/.sdkman/*/current/bin -maxdepth 0)
