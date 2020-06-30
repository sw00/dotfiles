[ -d "$HOME/.cargo/bin" ] && \
  PATH="$HOME/.cargo/bin:$PATH"

[ -n `command -v rustc`l ] && \
  export RUST_SRC_PATH=$(rustc --print sysroot)/lib/rustlib/src/rust/src
