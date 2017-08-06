# How to Create Ubuntu Image Using Disk Image Builder (DIB)

# Introduction

Ubuntu is nice to have on a VM locally on your laptop.  E.g., if you're on Windows and want
to do Linux-type work.

Back in the day, I thought that to get Ubuntu, it's pretty straightforward:

* Download the ISO
* Create a VM
* Mount the ISO in the virtual CD
* Boot from CD
* Answer all the questions
* ...and eventually, you'll get to the Ubuntu GUI.
* Then login, disable the GUI (because you don't need it), etc.
* Add your username
* Add your keys

Recently, I was doing some research on nodepool which led me to do research on Disk Image Builder.
At the end of my research, I realized that the above method of getting a Ubuntu image on your
laptop is a bit dated and way too manual and needlessly painful.  The easier say is to use Disk
Image Builder.

# Tutorial Part

This tutorial will show how I created a Ubuntu (Xenial) image, and booted it up on my Mac
running VMware Fusion.  The image will be created so that it has these already installed.

* an ssh key for the user on my host running the disk-image-create command
* a user 'dperique' with password 'password' for easy (BUT INSECURE! -- so be careful) access

This means that once you boot the image (you are about to create), you will be able to ssh as the user
you used to create the image (probably yourself) or login on the console as 'dperique' (I chose my
username -- you can use yours instead).

All of this will be done on the command line with no GUI involved using [Disk Image Builder] (DIB) and
two popular DIB elements -- [local-config] and [devuser].
[Disk Image Builder]: https://docs.openstack.org/diskimage-builder/latest/



[local-config]: https://docs.openstack.org/developer/diskimage-builder/elements/local-config/README.html
[devuser]: https://docs.openstack.org/developer/diskimage-builder/elements/devuser/README.html

The commands below are assumed to be running on Ubuntu (16.04 in my case); I don't see any reason why
they would not work for Centos (but you'll have to use yum vs. apt-get below) or other versions of Ubuntu.
Once you get your Ubuntu VM up on your laptop, you can run these commands there.  But before that, you'll
need access to another
Ubuntu machine.

First, you'll need to install pip to get DIB:

```
$ apt-get update && sudo apt-get -y upgrade
$ apt-get install python-pip
```

or

```
$ apt-get -y install python-pip
$ pip install --upgrade pip
```

Install Disk Image Builder and other things it needs:

```
$ pip install diskimage-builder
$ apt-get -y install qemu-utils debootstrap kpartx
```

Set some variables for the user we want automatically added -- these are used by the `devuser` element.  See
the doc for more variables you can use.

```
DIB_DEV_USER_USERNAME=dperique
DIB_DEV_USER_PASSWORD=password
```

This command creates a qcow2 image.  Notes:

* the key of the user running the command is installed at /root/.ssh/authorized_keys
* we specify the local-config and devuser elements as mentioned above
* we use —image-size 4G to give the resulting image a size of 4G to give some good amount of free space in the VM; the default is 1.5G.

```
$ disk-image-create —image-size 4G -o ~/dp-ubuntu vm ubuntu local-config devuser
```

Convert the image to vmdk format for VMware Fusion:

```
$ qemu-img convert -f qcow2 dp-ubuntu.qcow2 -O vmdk dp-ubuntu.vmdk
```

For Virtual Box, you will need the .vdi format.  Convert the image to vdi format for Virtual Box like this:

```
$ qemu-img convert -f qcow2 ../dp-ubuntu.qcow2 -O vdi dp-ubuntu.vdi
```

Get the .vmdk to your machine that has VMware Fusion installed.  You can use scp for example.

Create a VM in VMware Fusion and tell Fusion to use the .vmdk image file you just copied.  Here's what
I did on my VMware Fusion UI:

* New VM
* Create customVM, Ubuntu 64
* Use an existing virtual disk
* Navigate to your .vmdk you just created
* Select the 'take disk away’ option
* Note the size is 4G as specified in —image-size above
* Now customize the VM as needed by giving more or less CPU/RAM than the defaults
* When you get to the Ethernet, choose Advanced and generate the MAC address.  You will use that in the
DHCP configuration below.

Setup VMware fusion so that you can get a static IP address.  You will need this static IP address to
ssh into the newly created VM.  This is optional if you can determine the IP address another way
(e.g., login as 'dperique' and password at the prompt on the console and run 'ifconfig').

```
$ sudo vi /Library/Preferences/VMware Fusion/vmnet8/dhcpd.conf
<after this line, insert the host configuration>
####### VMNET DHCP Configuration. End of "DO NOT MODIFY SECTION" #######
host dp-ubuntu-64 {
    hardware ethernet 00:50:56:2D:00:12;  <— get MAC address from generate option on VM settings
    fixed-address  192.168.184.99;
}
```

Quit and restart VMware Fusion for the changes to take effect.

Boot the VM, wait until you see the username prompt, then you should be able to ssh into the VM using your key
and user when you created the VM.

```
ssh <myuser>@192.168.184.99
```

Do the usual things you’d do to get Ubuntu up and running.  I like to install docker but you may like to
install other things:

```
$ sudo apt-get update
$ apt-get install docker.io
$ ifconfig ;# and you should see docker0 interface
```

Confirm the ‘dperique’ user is present (login with user/password dperiquet/password) or ssh as your username
and look for the dperique home directory:

$ ls /home/dperique


Note that you can use the same commands above to create a centos VM as well.

Notice there was very little interaction involved -- no GUIs and questions to answer and no adding your
key and/or username/password manually.  I know going forward, I will most likely never use the old "install
from ISO method" again.
