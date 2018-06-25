# Use this if you have direct access to root account.

# node 1-6 maps to each Kubernetes node in alphabetical order.
#

## Copy the certificates and restore them.

for i in 1 2 3 ; do
  mkdir -p kube/node$i
  mkdir -p etcd/node$i
  mkdir -p share/node$i
done

j=1
for i in 236.111 236.206 236.229 ; do
  scp -i junk.rsa root@192.168.$i:/etc/kubernetes/ssl/* ./kube/node$j
  scp -i junk.rsa root@192.168.$i:/etc/ssl/etcd/ssl/* ./etcd/node$j
  scp -i junk.rsa root@192.168.$i:/usr/local/share/ca-certificates/* ./share/node$j
  j=$((j+1))
done

# After you are done, please verify you have the certificates!
# Do not wait until a disaster to find out your certificates didn't get saved.
