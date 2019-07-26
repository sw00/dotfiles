#!/bin/bash
set -e

NONDOT=(bin Brewfile scripts)
EXCLUDE=(extra-settings iterm2 'secrets\*')

case $(uname -s) in 
	"Darwin")
		OS=macos;;
	"Linux")
		OS=linux;;
esac		

[[ $OS = 'linux' && -n $(uname -r | grep Microsoft) ]] && \
	OS='wsl'

install_rcm() {
	pushd /tmp
	curl -LO https://thoughtbot.github.io/rcm/dist/rcm-1.3.3.tar.gz &&

	sha=$(sha256sum rcm-1.3.3.tar.gz | cut -f1 -d' ') &&
	[ "$sha" = "935524456f2291afa36ef815e68f1ab4a37a4ed6f0f144b7de7fb270733e13af" ] &&

	tar -xvf rcm-1.3.3.tar.gz &&
	cd rcm-1.3.3 &&

	./configure &&
	make &&
	sudo make install
	popd
}

[[ -z $(command -v rcup) ]] && \
	install_rcm

rcup ${NONDOT[@]/#/-U } ${EXCLUDE[@]/#/-x } -t $OS

install_pyenv() {
	git clone --depth=1 https://github.com/pyenv/pyenv ~/.pyenv
	[[ -z $(cat ~/.profile | grep PYENV_ROOT) ]] && \
		echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.profile && \
		echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bash_profile && \
		echo -e 'if command -v pyenv 1>/dev/null 2>&1; then\n  eval "$(pyenv init -)"\nfi' >> ~/.bash_profile
}

while [ ! $# -eq 0 ]
do
	case "$1" in
		--pyenv)
			install_pyenv
			exit
			;;
	esac
	shift
done
