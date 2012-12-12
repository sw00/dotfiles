#backup old .vim directory
mv $HOME/.vim $HOME/.vim.old
mv $HOME/.vimrc $HOME/.vimrc.old

# create symlinks for repo
ln -s $PWD/vim $HOME/.vim
ln -s $PWD/vimrc $HOME/.vimrc
