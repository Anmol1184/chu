# **Install Arch Linux**

##### ***Update system clock***

```bash
timedatectl set-ntp true
timedatectl status
```

##### *Set disk for install*

Identify the internal storage device where Arch Linux will be installed by running `lsblk -f`.

##### *Partition disk*

Layout for a single SSD with a GPT partition table that contains two partitions:

- Partition 1 - EFI boot partition (ESP) - size `1GiB`, code `ef00`
- Partition 2 - root partition - remaining storage

##### ***Format partitions***

ESP partition (partition #1) is formatted with the `vfat` filesystem, and the Linux root use `btrfs` ...

I am using `/dev/sda1` as EFI and `/dev/sda2` as root partition.

```bash
mkfs.vfat -F32 -n ESP /dev/sda1
mkfs.btrfs -L archlinux /dev/sda2
```

##### *Mount root device*

```bash
mount /dev/sda2 /mnt
```

##### *Create BTRFS subvolumes*

Each BTRFS filesystem has a top-level subvolume with `ID=5`. A subvolume is a part of the filesystem with its own independent data.

Creating subvolumes on a BTRFS filesystem allows the separation of data. This is particularly useful when creating backup snapshots of the system. An example scenario might be where its desirable to rollback a system after a broken upgrade, but any changes made in a user's `/home` directory should be left alone.

Changing subvolume layouts is made simpler by not mounting the top-level subvolume as `/` (the default). Instead, create a subvolume that contains the actual data, and mount _that_ to `/`.

Use `@` for the name of this new subvolume (which is the default for [Snapper](https://wiki.archlinux.org/title/Snapper), a tool for making backup snapshots) ...

```bash
btrfs subvolume create /mnt/@
```

I create additional subvolumes for more fine-grained control over rolling back the system to a previous state, while preserving the current state of other directories. These subvolumes will be excluded from any root subvolume snapshots:

**Subvolume** -- **Mountpoint**

- `@home` -- `/home` (preserve user data)
- `@snapshots` -- `/.snapshots`
- `@cache` -- `/var/cache`
- `@libvirt` -- `/var/lib/libvirt` (virtual machine images)
- `@log` -- `/var/log` (excluding log files makes troubleshooting easier after reverting `/`)
- `@tmp` -- `/var/tmp`

The reasoning behind not excluding the entire `/var` out of the root snapshot is that `/var/lib/pacman` database in particular should mirror the rolled back state of installed packages.

```bash
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@cache
btrfs subvolume create /mnt/@libvirt
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@tmp
```

##### *Mount subvolumes*

Unmount the root partition ...

```bash
umount /mnt
```

Set mount options for the subvolumes ...

```bash
export sv_opts="rw,noatime,compress-force=zstd:1,space_cache=v2"
```

Mount the new BTRFS root subvolume with `subvol=@` ...

```bash
mount -o ${sv_opts},subvol=@ /dev/sda2 /mnt
```

Create mountpoints for the additional subvolumes ...

```bash
mkdir -p /mnt/{home,.snapshots,var/cache,var/lib/libvirt,var/log,var/tmp}
```

Mount the additional subvolumes ...

```bash
mount -o ${sv_opts},subvol=@snapshots /dev/sda2 /mnt/.snapshots
mount -o ${sv_opts},subvol=@cache /dev/sda2 /mnt/var/cache
mount -o ${sv_opts},subvol=@libvirt /dev/sda2 /mnt/var/lib/libvirt
mount -o ${sv_opts},subvol=@log /dev/sda2 /mnt/var/log
mount -o ${sv_opts},subvol=@tmp /dev/sda2 /mnt/var/tmp
```

##### *Mount ESP partition*

```bash
mkdir /mnt/efi
mount /dev/sda1 /mnt/efi
```

##### *Install base system*

Select an appropriate [microcode](https://wiki.archlinux.org/title/Microcode) package to load updates and security fixes from processor vendors.

Depending on the processor, set `microcode` for Intel ...

```bash
export microcode="intel-ucode"
```

For AMD ...

```bash
export microcode="amd-ucode"
```

Install the base system ...

```bash
pacstrap /mnt base base-devel ${microcode} btrfs-progs linux-zen linux-zen-headers nano linux-firmware bash-completion htop man-db networkmanager pacman-contrib
```

##### *Fstab*

```bash
genfstab -U -p /mnt >> /mnt/etc/fstab
```

## Configure

Chroot into the base system to configure ...

```bash
arch-chroot /mnt /bin/bash
```

##### *Timezone*

Set desired timezone (example: `America/Toronto`) and update the system clock ...

```bash
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc
```

##### *Hostname*

Assign a hostname (example: `arch`) ...

```bash
echo "arch" > /etc/hostname
```

Add matching entries to `/etc/hosts` ...

```bash
nano /etc/hosts
```

```bash
127.0.0.1   localhost
::1         localhost
127.0.1.1   arch.localdomain arch
```

##### *Locale*

Set locale (example: `en_US.UTF-8`) ...

```bash
export locale="en_US.UTF-8"
sed -i "s/^#\(${locale}\)/\1/" /etc/locale.gen
echo "LANG=${locale}" > /etc/locale.conf
locale-gen
```

##### *Editor*

Set a system-wide default editor (example: `nano`) ...

```bash
echo "EDITOR=nano" > /etc/environment && echo "VISUAL=nano" >> /etc/environment
```

##### *Root password*

Assign password to `root` ...

```bash
passwd
```

##### *Add user*

Create a user account (example: `ani`) with superuser privileges ...

```bash
useradd -m -G wheel -s /bin/bash ani
passwd ani
```

Activate `wheel` group access for `sudo` ...

```bash
sed -i "s/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/" /etc/sudoers
```

##### *NetworkManager*

Enable `NetworkManager` to start at boot ...

```bash
systemctl enable NetworkManager
```

Wired network connection is activated by default. Run `nmtui` in the console and choose `Activate a connection` to setup a wireless connection.

##### *Mkinitcpio*

Set necessary `FILES` and `MODULES` and `HOOKS` in `/etc/mkinitcpio.conf`:

***MODULES***

Add `btrfs` support to mount the root filesystem ...

```bash
MODULES=(btrfs)
```

##### *Boot loader: GRUB*

Install ...

```bash
pacman -S grub efibootmgr
```

##### *Install boot loader*

Install GRUB in the ESP ...

```bash
grub-install --target=x86_64-efi --efi-directory=/efi --boot-directory=/efi --bootloader-id=GRUB
```

Verify that a `GRUB` entry has been added to the UEFI bootloader by running ...

```bash
efibootmgr
```

Generate the GRUB configuration file ...

```bash
grub-mkconfig -o /efi/grub/grub.cfg
```


##### *Reboot*

Exit chroot and reboot ...

```bash
exit
umount -R /mnt
reboot
```


#### After the install
##### *Package manager*

Bring some color and the spirit of _Pacman_ to `pacman` with `Color` and `ILoveCandy` options.

Modify `/etc/pacman.conf` ...

```bash
# Misc options
Color
ILoveCandy
```

##### *Sound*

```bash
sudo pacman -S pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber alsa-utils
```

##### *AUR*

[Arch User Repository](https://aur.archlinux.org/) (AUR) is a community-driven software package repository.

Compile/install/upgrade packages [manually](https://wiki.archlinux.org/title/Arch_User_Repository#Installing_and_upgrading_packages) or use an AUR helper application.

_Example:_ Install AUR helper `yay` ...

```bash
git clone https://aur.archlinux.org/yay-git.git
cd yay-git
makepkg -si
```



# ==ZRAM swap on Arch Linux==

Swap space can take the form of a disk partition or a file. Users may create a swap space during installation or at any later time as desired. Swap space can be used for two purposes, to extend the virtual memory beyond the installed physical memory (RAM), and also for [suspend-to-disk](https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate "Power management/Suspend and hibernate") support.

To check swap status, use:

```
swapon --show
```

##### *Swap partition*

A [swap partition](https://wiki.archlinux.org/title/Partitioning#Swap "Partitioning") can be created with most GNU/Linux [partitioning tools](https://wiki.archlinux.org/title/Partitioning_tools "Partitioning tools").

To set up a partition as Linux swap area, the [mkswap(8)](https://man.archlinux.org/man/mkswap.8) command is used. For example:

```
mkswap /dev/sdxy
```

To enable the device for paging:

```
swapon /dev/sdxy
```

##### *Enabling at boot*

To enable the swap partition at boot time:

Add an entry to `/etc/fstab`. E.g.:

```
UUID=_device_UUID_ none swap defaults 0 0
```

where the `_device_UUID_` is the [UUID](https://wiki.archlinux.org/title/UUID "UUID") of the swap space.

##### *Hibernation*

In order to use hibernation, you must create a [swap](https://wiki.archlinux.org/title/Swap "Swap") partition or file, [configure the initramfs](https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate#Configure_the_initramfs) so that the resume process will be initiated in early userspace, and specify the location of the swap space in a way that is available to the initramfs, e.g. `HibernateLocation` EFI variable defined by [systemd](https://wiki.archlinux.org/title/Systemd "Systemd") or `resume=` [kernel parameter](https://wiki.archlinux.org/title/Kernel_parameter "Kernel parameter"). These three steps are described in detail below.

##### *Configure the initramfs*

When using a busybox-based [initramfs](https://wiki.archlinux.org/title/Initramfs "Initramfs"), which is the default, the `resume` hook is required in `/etc/mkinitcpio.conf`. Whether by label or by UUID, the swap partition is referred to with a udev device node, so the `resume` hook must go _after_ the `udev` hook. This example was made starting from the default hook configuration:

```
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems resume fsck)
```

Remember to [regenerate the initramfs](https://wiki.archlinux.org/title/Regenerate_the_initramfs "Regenerate the initramfs") for these changes to take effect.

##### *Pass hibernate location to initramfs*

he [kernel parameter](https://wiki.archlinux.org/title/Kernel_parameter "Kernel parameter") `resume=_swap_device_` can be used, where _swap_device_ follows the [persistent block device naming](https://wiki.archlinux.org/title/Persistent_block_device_naming "Persistent block device naming"). For example:

- `resume=UUID=4209c845-f495-4c43-8a03-5363dd433153`
- `resume="PARTLABEL=Swap partition"`

Edit `/etc/default/grub` and append your kernel options between the quotes in the `GRUB_CMDLINE_LINUX_DEFAULT` line:

```
GRUB_CMDLINE_LINUX_DEFAULT="resume=UUID=4209c845-f495-4c43-8a03-5363dd433153 quiet splash"
```

And then automatically re-generate the `grub.cfg` file with:

```
grub-mkconfig -o /boot/efi/grub.cfg
```

The kernel parameters will only take effect after rebooting. To hibernate right away, obtain the volume's major and minor device numbers from [lsblk](https://wiki.archlinux.org/title/Lsblk "Lsblk") and echo them in format `_major_:_minor_` to `/sys/power/resume`.

For example, if the swap device is `8:3`:

```
echo 8:3 > /sys/power/resume
```
If using a swap file, additionally follow the procedures in [#Acquire swap file offset](https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate#Acquire_swap_file_offset).


# ==Virtualization using KVM + QEMU + libvirt==

[KVM](https://en.wikipedia.org/wiki/Kernel-based_Virtual_Machine) (Kernel-based Virtual Machine) is built into the Linux kernel and handles the CPU and memory details. [QEMU](https://en.wikipedia.org/wiki/QEMU) (Quick EMUlator) emulates the various hardware components of a physical machine. Finally, [libvirt](https://wiki.archlinux.org/title/Libvirt) provides the tools for creating and managing VMs. I use `virt-manager` and `virsh` as graphical and console interfaces respectively.

