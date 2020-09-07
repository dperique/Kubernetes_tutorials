# Using qcow2 backing images
When you create VMs, using kvm for example, you will need a lot of disk space for all
of your images.  Sometimes you just don't have enough disk space.

NOTE: saving money on disk space is one of best ways to lose money/value.  Having to
add a disk later or increase the size of your disk, etc. is costly because of downtime
and disruption.  Never cut costs by reducing disk space unless you really have a great
handle on what you are doing!  This has cost $1000s per hour in my past.

To help mitigate the disk usage problem, you can use qcow2 images that allow you to
use a single "backing" disk.  For example, I create a Ubuntu image that is about 20G.
I can then create instances of Ubuntu using that same disk as a backing disk; in this
way, each Ubuntu instance uses a smaller disk image.  The disk image used by individual
Ubuntu instances will contain only the differences from the backing disk.

```
# Create a "base" image to serve as your "backing" disk image.
#
qemu-img create -f qcow2 ubuntu_base.img 20G

# Create an image for your first ubuntu VM using this "base" image.
#
qemu-img create -f qcow2 -b ubuntu_base.img ubuntu1.img

# Get info on your base disk -- it will show 20G.
#
qemu-img info ubuntu_base.img

# Get info on your VM disk -- it will show that it uses the "backing" disk.
#
qemu-img info ubuntu1.img
```
