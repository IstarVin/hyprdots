#!/usr/bin/env bash
#|---/ /+--------------------------+---/ /|#
#|--/ /-| Custom install script    |--/ /-|#
#|-/ /--| IstarVi                    |-/ /--|#
#|/ /---+--------------------------+/ /---|#

scrDir=$(dirname "$(realpath "$0")")
source "${scrDir}/global_fn.sh"
if [ $? -ne 0 ]; then
	echo "Error: unable to source global_fn.sh..."
	exit 1
fi
CfgDir="${cloneDir}/Configs"

diskUUID="a670b2de-99ca-43e3-8c34-3fc50150c12e"

function aj_disk() {
	if sudo blkid | grep $diskUUID >/dev/null 2>&1; then
		sudo mkdir /mnt/AJ/
		sudo chown "$USER:$USER" /mnt/AJ/
		echo -ne "
# AJ
UUID=$diskUUID /mnt/AJ btrfs defaults 0 2
" | sudo tee -a /etc/fstab

		sudo mount -a
		sudo systemctl daemon-reload

		ln -sf /mnt/AJ "$HOME/AJ"
		rm -rf "$HOME/{Documents,Downloads,Pictures,Projects,Videos}"
		ln -sf /mnt/AJ/{Documents,Downloads,Pictures,Projects,Videos} "$HOME"

		cp -r /mnt/AJ/.ssh/ "$HOME"
		cwd=$(pwd)
		cd /mnt/AJ/Projects/dots-hyprland
		bash link_configs.sh
		cd "$cwd"

		mkdir ~/.hehe
	fi
}

# ROG install
function rog_install() {
	if ! pacman -Q cachyos-mirrorlist >/dev/null 2>&1; then
		sudo pacman-key --recv-keys 8F654886F17D497FEFE3DB448B15A6B0E9A3FA35
		sudo pacman-key --finger 8F654886F17D497FEFE3DB448B15A6B0E9A3FA35
		sudo pacman-key --lsign-key 8F654886F17D497FEFE3DB448B15A6B0E9A3FA35
		sudo pacman-key --finger 8F654886F17D497FEFE3DB448B15A6B0E9A3FA35

		wget "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x8b15a6b0e9a3fa35" -O /tmp/g14.sec
		sudo pacman-key -a /tmp/g14.sec
		rm /tmp/g14.sec

		echo -ne "
 [g14]
 Server = https://arch.asus-linux.org
 " | sudo tee -a /etc/pacman.conf
	fi

	sudo pacman -Suy --noconfirm asusctl power-profiles-daemon supergfxctl switcheroo-control
	sudo systemctl enable --now power-profiles-daemon supergfxd switcheroo-control
}

function evremap_install() {
	yay -S --noconfirm evremap
	sudo cp -f "$CfgDir/.evremap/evremap.toml" /etc
	sudo cp -f "$CfgDir/.evremap/evremap.service" /etc/systemd/user
	sudo systemctl enable --now evremap
}

function plymouth_install() {
	yay -S --noconfirm plymouth plymouth-theme-archlinux
	if pacman -Q grub >/dev/null 2>&1; then
		sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& splash/' /etc/default/grub
		sudo sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/' /etc/default/grub

		sudo sed -i '/echo "\$message"/d' /etc/grub.d/10_linux

		sudo grub-mkconfig -o /boot/grub/grub.cfg
	fi

	sudo sed -i '/^HOOKS/s/udev/& plymouth/' /etc/mkinitcpio.conf

	sudo plymouth-set-default-theme -R archlinux
}

function setup_qemu() {
	yay -S --noconfirm qemu-desktop libvirt edk2-ovmf virt-manager ebtables dnsmasq
	yay -S --noconfirm looking-glass-git looking-glass-module-dkms-git
	sudo mkdir -p /etc/libvirt/hooks/qemu.d && sudo wget 'https://asus-linux.org/files/vfio/libvirt_hooks/qemu' -O /etc/libvirt/hooks/qemu && sudo chmod +x /etc/libvirt/hooks/qemu
	sudo systemctl enable --now libvirtd

	sudo usermod -aG libvirt,kvm,input "$USER"

	if sudo blkid | grep $diskUUID >/dev/null 2>&1; then
		virsh -c qemu:///system define /mnt/AJ/.vm/win11.xml
		sudo cp -R /mnt/AJ/.dots/etc/libvirt/ /etc
	fi

	virsh -c qemu:///system net-start default
	virsh -c qemu:///system net-autostart default

	echo -ne "
user = \"$USER\"
cgroup_device_acl = [
    \"/dev/null\", \"/dev/full\", \"/dev/zero\",
    \"/dev/random\", \"/dev/urandom\", \"/dev/ptmx\",
    \"/dev/kvm\", \"/dev/rtc\", \"/dev/hpet\", \"/dev/kvmfr0\"
 ]
 group = \"kvm\"
 " | sudo tee -a /etc/libvirt/qemu.conf

	echo -ne "
#KVMFR Looking Glass Module
kvmfr
" | sudo tee /etc/modules-load.d/kvmfr.conf

	echo -ne "
#KVMFR Looking Glass Module
options kvmfr static_size_mb=32
" | sudo tee /etc/modprobe.d/kvmfr.conf

	echo -ne "
SUBSYSTEM==\"kvmfr\", OWNER=\"$USER\", GROUP=\"kvm\", MODE=\"0660\"
" | sudo tee /etc/udev/rules.d/99-kvmfr.rules
}

function waydroid_install() {
	yay -S waydroid waydroid-image python-pyclipper --noconfirm
	waydroid prop set persist.waydroid.width 1920
	waydroid prop set persist.waydroid.height 1080
	waydroid prop set persist.waydroid.fake_wifi "com.internet.speed.meter.lite"
}

function nvidia_install() {
	gpu_type=$(lspci)
	if grep -E "NVIDIA|GeForce" <<<"${gpu_type}"; then
		kernel_type=$(uname -r | cut -d "-" -f 4)
		if [ -z "$kernel_type" ]; then
			yay -S linux-headers
		else
			yay -S "linux-$kernel_type-headers"
		fi
		yay -S nvidia-dkms
	else
		echo "No NVIDIA found skipping..."
	fi
}

function makepkg_patch() {
	TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
	nc=$(nproc --all)
	if [[ $TOTAL_MEM -gt 8000000 ]]; then
		sudo sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$nc\"/g" /etc/makepkg.conf
		sudo sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $nc -z -)/g" /etc/makepkg.conf
	fi
}

if [ "$1" = "run" ]; then
	aj_disk
	rog_install
	evremap_install
	plymouth_install
fi
