# locale
export LC_ALL=en_US.UTF-8 LC_TYPE=en_US.UTF-8 LANG=en_US.UTF-8

# use VcXsrv on WSL to share clipboard
LOCAL_IP=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
export DISPLAY=$LOCAL_IP:0
export LIBGL_ALWAYS_INDIRECT=1

# let vagrant speak to virtualbox
export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS="1"
