#!/bin/bash
clear
set -e 
echo " welcome to GCE cluster installation, jenkins installation in k8s ns jenkins" 
echo " relax for some minutes and get a coffee :) " 
error_exit()
{
    echo "$1" 1>&2
    exit 1
}

# Check for cluster name as first (and only) arg
CLUSTER_NAME=${1-jenkins-test}
NUM_NODES=1
MACHINE_TYPE=n1-standard-4
NETWORK=default
ZONE=europe-west1-d

# Source the config
if ! gcloud container clusters describe ${CLUSTER_NAME} > /dev/null 2>&1; then
  echo "* Creating Google Container Engine cluster \"${CLUSTER_NAME}\"..."
  # Create cluster
  gcloud container clusters create ${CLUSTER_NAME} \
    --num-nodes ${NUM_NODES} \
    --machine-type ${MACHINE_TYPE} \
    --scopes "https://www.googleapis.com/auth/projecthosting,https://www.googleapis.com/auth/devstorage.full_control,https://www.googleapis.com/auth/monitoring,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/compute,https://www.googleapis.com/auth/cloud-platform" \
    --zone ${ZONE} \
    --network ${NETWORK} || error_exit "Error creating Google Container Engine cluster"
  echo "done."
else
  echo "* Google Container Engine cluster \"${CLUSTER_NAME}\" already exists..."
fi

# Make kubectl use new cluster
echo "* Configuring kubectl to use ${CLUSTER_NAME} cluster..."
gcloud container clusters get-credentials ${CLUSTER_NAME} --zone ${ZONE}
echo "done."

echo "Getting Jenkins artifacts"
if [ ! -d continuous-deployment-on-kubernetes ]; then
  git clone https://github.com/ndonthiNLI/continuous-deployment-on-kubernetes.git
fi

echo "Deploying Jenkins to Google Container Engine..."
pushd continuous-deployment-on-kubernetes

if ! gcloud compute images describe jenkins-home-image-test > /dev/null 2>&1; then
  echo "* Creating Jenkins home image test"
  gcloud compute images create jenkins-home-image-test --source-uri https://storage.googleapis.com/solutions-public-assets/jenkins-cd/jenkins-home-v2.tar.gz
else
  echo "* Jenkins home image already exists"
fi

if ! gcloud compute disks describe jenkins-home-test --zone ${ZONE} > /dev/null 2>&1; then
  echo "* Creating Jenkins home test disk"
  gcloud compute disks create jenkins-home-test --image jenkins-home-image-test --zone ${ZONE}
else
  echo "* Jenkins home test disk already exists"
fi

PASSWORD=`openssl rand -base64 15`; echo "Your Jenkins password is $PASSWORD"; sed -i.bak s#CHANGE_ME#$PASSWORD# jenkins/k8s/options
kubectl create ns jenkins
kubectl create secret generic jenkins --from-file=jenkins/k8s/options --namespace=jenkins
kubectl apply -f jenkins/k8s/
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /tmp/tls.key -out /tmp/tls.crt -subj "/CN=jenkins/O=jenkins"
kubectl create secret generic tls --from-file=/tmp/tls.crt --from-file=/tmp/tls.key --namespace jenkins
kubectl apply -f jenkins/k8s/lb/ingress.yaml
popd
echo "done."

echo "All resources deployed."
echo "In a few minutes your loadBalancer will finish provisioning. You can run the following to get its IP address:"
echo "kubectl get ingress jenkins --namespace jenkins -o \"jsonpath={.status.loadBalancer.ingress[0].ip}\";echo"
echo
echo "Login with user: jenkins and password ${PASSWORD}"
