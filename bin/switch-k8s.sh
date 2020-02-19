#!/usr/bin/env bash

case "$1"
in
	ska)
		echo switching to engageska
		cp -f ~/.kube/.engageska.kubeconfig ~/.kube/config
	;;
	ska2)
		echo switching to ct-test
		cp -f ~/.kube/.ct-test.kubeconfig ~/.kube/config
	;;
	local)
		echo switching to local
		cp -f ~/.kube/.local.kubeconfig ~/.kube/config
	;;
esac
