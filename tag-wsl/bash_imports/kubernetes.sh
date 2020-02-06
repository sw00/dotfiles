# use kubeconfig from windows
mkdir -p ~/.kube
ln -sf /mnt/c/Users/$(wslvar USERNAME)/.kube/config ~/.kube/config
