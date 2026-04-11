# dotfiles

This repo is going to be an ongoing collection of script and configs
for bootstrapping my system on void linux. 

A couple reasons i like void linux:
- runit is super simple and > systemd and openrc
- xbps is a great and intuitive package manger
- reasonablly up-to-date packages while being stable
- option of glibc or musl which is cool

Although I just wrote the most crap install scrip, the niceties
it will have over the default void installer is:
- encrypted disk
- limine over grub
- asthetic splash/boot screen

basically it takes out the need to ever have to install this distro from the commandline again.
It will be super easy also in the future to write a post-install script to then setup
a window manager, tools..etc.

Some immediate todos for the script (when i get more time)
- dont hard-code everything -> get some user input e.g. name and password. auto-detect everything else. This will actually make this usable
- unpack tar instead of xbps. this allows us to install from any distro or live env. 
- get rid of any bashisms and stick to posix shell
- re-write more modular, clean and check of 'nice' / missing flags for tools
- add error handling
- capture stdout, and just write our own progress bar / steps insead of all the junk currently on the screen
