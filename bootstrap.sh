#!/bin/bash
set -e

NONDOT=(bin Brewfile scripts)
EXCLUDE=(bootstrap.sh extra-settings iterm2 'secrets\*')
COPY=(profile bashrc gitconfig)

case $(uname -s) in
	"Darwin")
		OS=macos
		PKG_INSTALL_CMD='brew install';;
	"Linux")
		if [[ -n $(uname -r | grep -i microsoft) ]]; then
			OS='wsl'
		else
			OS=linux
		fi
		PKG_INSTALL_CMD='sudo apt install -yq'
;;
esac

install_if_missing() {
	CMD=$1
	[[ -n $2 ]] && PKG=$2 || PKG=$1
	
	if [[ -z $(command -v $CMD) ]]; then
		$PKG_INSTALL_CMD $PKG
	fi
}

mac_xor_linux() {
	IF_MAC=$1
	IF_LINUX=$2

	[[ $OS == macos ]] && echo "$IF_MAC" || echo "$IF_LINUX"
}

download_file() {
	install_if_missing wget

	URL=$1
	FILENAME=$(basename "$URL")

	[[ ! -e "$FILENAME" ]] && wget "$URL"
}

install_rcm() {
	#dependencies
	install_if_missing make $(mac_xor_linx make build-essential)

	pushd /tmp
	download_file https://thoughtbot.github.io/rcm/dist/rcm-1.3.3.tar.gz

	sha=$(sha256sum rcm-1.3.3.tar.gz | cut -f1 -d' ') &&
	[ "$sha" = "935524456f2291afa36ef815e68f1ab4a37a4ed6f0f144b7de7fb270733e13af" ] &&

	tar -xvf rcm-1.3.3.tar.gz &&
	cd rcm-1.3.3 &&

	./configure &&
	make &&
	sudo make install
	popd
}

_install_deb() {
	pushd /tmp
	download_file $1
	debfile=$(echo $1 | rev | cut -d\/ -f1 | rev)
	sudo dpkg -i $debfile
	popd
}

install_pyenv() {
	[[ ! -d ~/.pyenv ]] && git clone --depth=1 https://github.com/pyenv/pyenv ~/.pyenv
	[[ -z $(cat ~/.profile | grep PYENV_ROOT) ]] && \
		echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.profile && \
		echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.profile && \

	if [[ $1 = 'with_virtualenv' ]]; then
		mkdir -p ~/.pyenv/plugins
		[[ ! -d ~/.pyenv/plugins ]] && git clone --depth=1 https://github.com/pyenv/pyenv-virtualenv.git ~/.pyenv/plugins/pyenv-virtualenv
		[[ -z $(cat ~/.bashrc | grep 'pyenv virtualenv-init') ]] && echo 'eval "$(pyenv virtualenv-init -)"' >> ~/.bashrc
	fi

	if [[ $OS = 'linux' || $OS = 'wsl' ]]; then
		sudo apt-get install -yq --no-install-recommends make build-essential zlib1g-dev libffi-dev libssl-dev libreadline-dev libbz2-dev libsqlite3-dev 
	fi
}

setup_pythons() {
	PY3_VERSION=3.7.3
	PY2_VERSION=2.7.17
	PIP_REQUIRE_VIRTUALENV=no

	pyenv install $PY3_VERSION
	pyenv shell $PY3_VERSION && pip install -U pip neovim

	pyenv install $PY2_VERSION
	pyenv shell $PY2_VERSION && pip install -U pip neovim
}

install_tmux() {
	install_if_missing tmux

	mkdir -p ~/.tmux/plugins
	[[ ! -d ~/.tmux/plugins/tpm ]] && git clone --depth=1 https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
}

install_ripgrep() {
	if [[ $OS = 'linux' || $OS = 'wsl' ]]; then
		_install_deb https://github.com/BurntSushi/ripgrep/releases/download/11.0.1/ripgrep_11.0.1_amd64.deb
	elif [[ $OS = 'macos' ]]; then
		brew install ripgrep
	fi
}

install_fd() {
	if [[ $OS = 'linux' || $OS = 'wsl' ]]; then
		_install_deb https://github.com/sharkdp/fd/releases/download/v7.3.0/fd-musl_7.3.0_amd64.deb
	elif [[ $OS = 'macos' ]]; then
		brew install fd
	fi
}

install_fzf() {
	[[ ! -d ~/.fzf ]] && git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
	cd ~/.fzf && ./install
}

install_autojump() {
	install_if_missing python

	if [[ $OS = 'macos' ]]; then
		brew install autojump
	else
		[[ ! -d /tmp/autojump ]] && git clone --depth=1 https://github.com/wting/autojump.git /tmp/autojump
		cd /tmp/autojump && ./install.py
	fi
}

install_bashit() {
	[[ ! -d ~/.bash_it ]] && git clone --depth=1 https://github.com/Bash-it/bash-it.git ~/.bash_it
	cd ~/.bash_it && ./install.sh
	sed -i "s/BASH_IT_THEME='bobby'/BASH_IT_THEME='norbu'/g" ~/.bashrc
}

install_fish() {
	[[ $OS = 'macos' ]] && \
		brew install fish
	[[ $OS = 'linux' || $OS = 'wsl' ]] && \
		sudo apt-get -yq install fish

	if [[ $1 = 'and_configure' ]]; then
		[[ ! -d ~/.oh_my_fish ]] && git clone --depth=1 https://github.com/oh-my-fish/oh-my-fish ~/.oh_my_fish
		cd ~/.oh_my_fish && bin/install --offline
		[[ $OS = 'linux' ]] && \
			omf install pbcopy
	fi
}

install_nvim() {
	install_if_missing ctags

	pushd ~/bin
	[[ -z $(command -v nvim) ]] && download_file https://github.com/neovim/neovim/releases/download/nightly/nvim.appimage
	mv nvim.appimage nvim
	chmod +x nvim
	popd
}

main() {
	[[ -z $(command -v rcup) ]] && \
			install_rcm

	RCUP_CMD="rcup ${NONDOT[@]/#/-U } ${EXCLUDE[@]/#/-x } -d `dirname $0` -t $OS"
	echo Running: $RCUP_CMD
	$RCUP_CMD

	while [ ! $# -eq 0 ]
	do
		case "$1" in
			--all)
				set +e
				install_pyenv with_virtualenv
				install_tmux
				install_ripgrep
				install_fd
				install_fzf
				install_autojump
				install_pyenv
				setup_pythons
				install_nvim
				install_fish
				exit
				;;
			--pyenv)
				install_pyenv with_virtualenv
				exit
				;;
			--tmux)
				install_tmux
				exit
				;;
			--rg)
				install_ripgrep
				exit
				;;
			--fd)
				install_fd
				exit
				;;
			--fzf)
				install_fzf
				exit
				;;
			--autojump)
				install_autojump
				exit
				;;
			--bashit)
				install_bashit
				exit
				;;
			--fish)
				install_fish and_configure
				exit
				;;
			--nvim)
				install_nvim
				exit
				;;
		esac
		shift
	done
}

main $@
