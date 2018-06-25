# Use this if you have direct access to ubuntu account with sudo

# node 1-6 maps to each Kubernetes node in alphabetical order.
#
for i in 1 2 3 4 5 6; do
  mkdir -p kube/node$i
  mkdir -p etcd/node$i
  mkdir -p share/node$i
done

# Tweak the for loop so that the IP addresses will be used correctly.
#
j=1
for i in `seq 34 40` ; do
  ssh -i junk.rsa ubuntu@192.168.1.$i "sudo tar czvf kube.tgz /etc/kubernetes/ssl/"
  ssh -i junk.rsa ubuntu@192.168.1.$i "sudo tar czvf etcd.tgz /etc/ssl/etcd/ssl/"
  ssh -i junk.rsa ubuntu@192.168.1.$i "sudo tar czvf share.tgz /usr/local/share/ca-certificates/"

  scp -i junk.rsa ubuntu@192.168.1.$i:kube.tgz ./kube/node$j
  scp -i junk.rsa ubuntu@192.168.1.$i:etcd.tgz ./etcd/node$j
  scp -i junk.rsa ubuntu@192.168.1.$i:share.tgz ./share/node$j
  j=$((j+1))
done

# After you are done, please verify you have the certificates!
# Do not wait until a disaster to find out your certificates didn't get saved.
