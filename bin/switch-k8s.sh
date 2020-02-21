#!/usr/bin/env bash

case "$1"
in
	ska)
		echo switching to engageska
		rm -f ~/.kube/config
		cp -f ~/.kube/.engageska.kubeconfig ~/.kube/config
	;;
	ska2)
		echo switching to ct-test
		rm -f ~/.kube/config
		cp -f ~/.kube/.ct-test.kubeconfig ~/.kube/config
	;;
	local)
		echo switching to local
		rm -f ~/.kube/config
		cp -f ~/.kube/.local.kubeconfig ~/.kube/config
	;;
esac
