#!/bin/bash

# I just noticed how old this script is.  Consider it a bash/kubectl demo.
# This functionality can be easily achieved using the kubectl rollout status
# command.

if [ "$1" == "" ] || [ "$2" == "" ]; then  
  echo ""
  echo "Usage kdeploy_check.sh <aDeploymentYaml> <aDeploymentName>"
  echo ""
  echo "  Given a deployment yaml, we do a 'kubectl create -f <aDeploymentYaml>'"
  echo "  and look for the replicas named in the deployment called <aDeploymentName>."
  echo "  Iterate and wait up to 10 iterations for them to be present."
  echo ""
  exit 0
fi

#set -o xtrace

aYaml=$1
aDpl=$2

# Create the deployment
#
kubectl create -f $aYaml

currRep=0
numRep=0

# Determine how many replicas we requested.
#
numRep=`kubectl get deployments $aDpl --output=jsonpath={.spec.replicas}`
if [ $? -eq 1 ]; then
  echo "Error looking up deployment '$aDpl'"
  exit 1
fi

good=0
for i in {1..10}; do 
  # Determine how many replicas that are currently available.
  # Returns empty string if none.
  #
  currRep=`kubectl get deployments $aDpl --output=jsonpath={.status.availableReplicas}`
  if [ "$currRep" == "" ]; then
    currRep=0
  fi

  echo "currently Available = '$currRep' out of '$numRep'"

  if [ "$currRep" -ne "$numRep" ]; then
    echo "All replicas not present after $i iterations"
    echo ""
    sleep 1
  else
    good=1
    break
  fi
done

if [ $good -eq 0 ]; then
  echo "Not all replicas came up"
  exit 1
else
  echo "All replicas came up"
  exit 0
fi
