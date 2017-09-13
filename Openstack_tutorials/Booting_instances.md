# Booting openstack instances (VMs) in various ways (Work in progress...)

## Introduction
Here, we show examples of booting openstack VMs using various commonly used parameters.
Doc doc is [here]
Another doc is [from IBM]
[here]: https://docs.openstack.org/cinder/latest/cli/cli-manage-volumes.html
[from IBM]: https://www.ibm.com/support/knowledgecenter/SSB27U_6.3.0/com.ibm.zvm.v630.hcpo3/bootnew.htm 

## Boot an instance from a volume
First, create the volume:

```
# Take a look at volumes already there
#
$ openstack volume list

# Delete a volume
#
$ openstack volume delete <NameOfVolume>

# Take a look at images already there
#
$ openstack image list

# Create a volume from a given image (e.g., Ubuntu 16.04) of 10G size.
#
openstack volume create --image <imageUUID> --size 10G --availability-zone <aName>

# Boot an instance with the volume you just created.
#
$ nova boot myTenGigVM --flavor 6 --block-device-mapping vda=<volumeUUID>:::0 --key-name <aKeyName> --nic net-name=<aNetName>
```



