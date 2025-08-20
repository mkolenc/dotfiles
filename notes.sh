### WIFI
-install iwd package
-enable dbus and iwd service
-enable network configuraiton for iwd:
	/etc/iwd/main.conf    
	[General]
	EnableNetworkConfiguration=true

### DWL
-install wget package
-wget the lates stable dwl release (current is 0.7)
	wget https://codeberg.org/dwl/dwl/releases/download/v0.7/dwl-v0.7.tar.gz
-extract the dwl archive
	tar xvzf dwl-v0.7.tar.gz
-Move into the directory
	cd dwl-v0.7
-install build-dependencies: base-devel (includes make,gcc pkg-config..etc good stuff) 
	xbps-install -S libinput libinput-devel wayland wayland-devel wlroots0.18 wlroots0.18-devel libxkbcommon libxkbcommon-devel wayland-protocols pkg-config
-build and install
	make install
-Install what dwl uses for program launcher and terminal by default: foot, wmenu
-install seatd and add user to _seatd group, and enable service
	xbps-install -S seatd
	ln -s /etc/sv/seatd/ /var/service
	usermod -aG _seatd mkolenc
-install the graphics driver (for my AMD thinkpad)
	xbps-install -S linux-firmware-amd mesa-dri vulkan-loader mesa-vulkan-radeon mesa-vaapi mesa-vdpau
-install a font: dejavu-fonts-ttf

### qutebrowser
-install qutebrowser
-install qt6-wayland .... kwayland and set vars as it say in docs

pipewire wants rtkit
wireplumber wants upower, xdg-desktop-portal-wlr

Also, alsa-utils needed for mic led

# most importat! remove speaker beeps!!!
Blacklisting the pcspkr and snd_pcsp modules will prevent udev from loading them at boot. Create the file:
/etc/modprobe.d/nobeep.conf
blacklist pcspkr
blacklist snd_pcsp

add this to bashrc or zsh:
export PATH="$HOME/.local/bin:$PATH"


install/enable acpi for sleep and handling hardware events.
- disable the lines which set the screen brightness in /etc/acpi/handler.sh though so it doesnt override
- our script

** Found a great orginization conventtion **
=> programs meant to be executed from command line directly go in .local/bin/* and dont have .sh 
=> Programs meant to be executed indirectly (e.g. status bar scripts...) go in .local/bin/<name>/* and end in .sh, or .py...
=> .local/share/* is for ??? not sure yet
=> .config<name> is for program config files (dwl build is there)

# Create this sudo vonfig -> dont need to touch /etc/suoders or use visudo
/etc/sudoers.d/wheel
	# Wait forever for password input
	Defaults passwd_timeout=0
	
	# Only re-ask every 5 minutes
	Defaults timestamp_timeout=5
	
	# Enable sudo privilege
	%wheel ALL=(ALL:ALL) ALL


