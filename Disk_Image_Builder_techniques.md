# Some Techniques used with Disk Image Builder

## Introduction
This doc lists a few techniques I used when creating my own images using disk image builder.

## Copy files from your host to the image
Think of this an "injecting" files into an image -- e.g., ssh keys, and other scripts that might
be useful to the user of the resultant image.

See the [Phase Subdirectories] doc for information on each element directory mentioned below.
[Phase Subdirectories]: https://media.readthedocs.org/pdf/diskimage-builder/latest/diskimage-builder.pdf

* Put the files you want to inject into some subdirectory on the local host running disk-image-create.
  This can be done via manual operation or via some ansible role that creates a nodepool machine 
  (as done in BonnyCI)
* write an element that uses these directories:
 - `exta-data.d`: In this directory, create a script that will copy the files from the local host to the $TMP_HOOKS_PATH
 - `install.d`: In this directory, create a script that will:
    - Create the directory on the image
    - Copy the files from $TMP_HOOKS_PATH to the directory on the image

Here's is my example of a file in /etc/mykeys/id_rsa.pub on the local host that I want copied to my
resultant image using disk-image create.  My element will be called 'copy_keys'.  And I will make it
so that the /etc/mykeys/id.pub.rsa file will be copied to /root/.ssh/authorized_keys on the image.

The element directory structure will be a subdirectory called 'copy_keys' and two subdirectories underneath it
called extra-data.d and install.d.  There will be one script inside each directory -- 99-copy-keys and 20-install-keys.

- elements
  - copy_keys
    - extra-data.d
      - 99-copy-keys
    - install.d
      - 20-install-keys

The 99-copy-keys script:

```
$ cat 99-copy-keys
#!/bin/bash

# This command is exected outside of chroot.
#
cp /etc/mykeys/id_rsa.pub $TMP_HOOKS_PATH
```

Note that the extra-data.d scripts are executed outside of chroot and so it has access to the local
host files.  You copy files to $TMP_HOOKS_PATH which is used by disk-image-create.

The 20-install-keys script:

```
$ cat 20-install-keys
#!/bin/bash

# These commands are exected in chroot on the image.
# The /tmp/in_target.d is where the keys are copied to when 99-copy-keys was executed.
#
mkdir /etc/mykeys
cp /tmp/in_target.d/id_rsa.pub /etc/mykeys
```

Note that the install.d scripts are exected in chroot so everything you do will affect the resultant
image.  The /tmp/in_target.d directory is available inside the image for files you copied using the
extra-data.d scripts.

The scripts must be executable -- if they are not, they are skipped.

Remeber to set your ELEMENTS_PATH environment variable to include the directory called `elements` above
so that disk-image-create can find your element.

You can run the disk-image-create command like this example:

```
$ disk-image-create --image-size 4G -o ~/myimage vm ubuntu copy_keys
```


