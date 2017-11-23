Forked from https://bitbucket.org/pkoltermann/git-config
--------------------------------------------------------
Thanks @pkoltermann

# Git configuration template

## Installation

1. Get the files

```bash
git clone https://github.com/bialas1993/git-config.git ~/.git-config
ln -sf ~/.git-config/gitconfig ~/.gitconfig
cp ~/.git-config/examples/.* ~/
```

2. Customize `~/.gitconfig_private` and `~/.gitignore_global`.
3. Voila.

## Global hooks
``` bash
git config --global init.templatedir '~/.git-config'
```
Command add global git directory struct - copy your hooks to any git repository when you execute `git init`
