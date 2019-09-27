#!/bin/bash
set -e

NONDOT=(bin Brewfile scripts)
EXCLUDE=(extra-settings iterm2 'secrets\*')
COPY=(profile bashrc bash_aliases gitconfig)

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

rcup ${NONDOT[@]/#/-U } ${EXCLUDE[@]/#/-x } -d `dirname $0` -t $OS

_install_deb() {
	pushd /tmp
	curl -LO $1
	debfile=$(echo $1 | rev | cut -d\/ -f1 | rev)
	sudo dpkg -i $debfile
	popd
}

install_pyenv() {
	git clone --depth=1 https://github.com/pyenv/pyenv ~/.pyenv
	[[ -z $(cat ~/.profile | grep PYENV_ROOT) ]] && \
		echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.profile && \
		echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.profile && \
		echo -e 'if command -v pyenv 1>/dev/null 2>&1; then\n  eval "$(pyenv init -)"\nfi' >> ~/.bashrc

	if [[ $1 = 'with_virtualenv' ]]; then
		mkdir -p ~/.pyenv/plugins
		git clone --depth=1 https://github.com/pyenv/pyenv-virtualenv.git ~/.pyenv/plugins/pyenv-virtualenv
		[[ -z $(cat ~/.bashrc | grep 'pyenv virtualenv-init') ]] && echo 'eval "$(pyenv virtualenv-init -)"' >> ~/.bashrc
	fi

	if [[ $OS = 'linux' || $OS = 'wsl' ]]; then
		sudo apt-get install -yq make build-essential libssl-dev libreadline-dev libbz2-dev libsqlite3-dev 
	fi
}


install_tpm() {
	mkdir -p ~/.tmux/plugins/tpm
	git clone --depth=1 https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
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
	git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
	cd ~/.fzf && ./install
}

install_autojump() {
	[[ $OS = 'macos' ]] && \
		brew install autojump
	[[ $OS = 'linux' || $OS = 'wsl' ]] && \
		git clone --depth=1 https://github.com/wting/autojump.git /tmp/autojump && \
		cd /tmp/autojump && ./install.py
}

install_bashit() {
	git clone --depth=1 https://github.com/Bash-it/bash-it.git ~/.bash_it
	cd ~/.bash_it && ./install.sh
	sed -i "s/BASH_IT_THEME='bobby'/BASH_IT_THEME='norbu'/g" ~/.bashrc
}

install_fish() {
	[[ $OS = 'macos' ]] && \
		brew install fish
	[[ $OS = 'linux' || $OS = 'wsl' ]] && \
		sudo apt-get install fish

	if [[ $1 = 'and_configure' ]]; then
		git clone --depth=1 https://github.com/oh-my-fish/oh-my-fish ~/.oh_my_fish
		cd ~/.oh_my_fish && bin/install --offline
		[[ $OS = 'linux' ]] && \
			omf install pbcopy
	fi
}


while [ ! $# -eq 0 ]
do
	case "$1" in
		--all)
			set +e
			install_pyenv with_virtualenv
			install_tpm
			install_ripgrep
			install_fd
			install_fzf
			install_autojump
			exit
			;;
		--pyenv)
			install_pyenv with_virtualenv
			exit
			;;
		--tpm)
			install_tpm
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
	esac
	shift
done
