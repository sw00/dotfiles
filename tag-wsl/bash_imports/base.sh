  # use VcXsrv on WSL to share clipboard
  LOCAL_IP=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
  export DISPLAY=$LOCAL_IP:0
  export LIBGL_ALWAYS_INDIRECT=1

  # let vagrant speak to virtualbox
  export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS="1"
