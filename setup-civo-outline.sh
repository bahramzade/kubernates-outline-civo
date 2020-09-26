#!/bin/bash
token=$1
clustername=$2

which curl &> /dev/null && which git &> /dev/null && which openssl &> /dev/null && which kubectl &> /dev/null
if [ $? -ne 0 ]; then
      echo "Required packages are not installed!"
      echo "Make sure you have install curl, git, openssl and kubectl"
      exit 1
fi

clusterid=`curl -H "Authorization: bearer $token" https://api.civo.com/v2/kubernetes/clusters 2>&1 | grep -oP  {\"id\":\"\([a-zA-Z0-9\-]*\)\",\"name\":\"$clustername\"  | awk -F\",\" '{print $1}'  | awk -F:\" '{print $2}'`

if [ -z "$clusterid" ]
then
      echo "No cluster exists with this name"
      echo "Create a cluster and proceed"
      exit 1
else
      echo $clusterid
      curl -H "Authorization: bearer $token" -X PUT https://api.civo.com/v2/kubernetes/clusters/$clusterid -d applications=Longhorn   &> /dev/null
      curl -H "Authorization: bearer $token" https://api.civo.com/v2/kubernetes/clusters/$clusterid 2>&1 | grep -oP  \"kubeconfig\":\"[^\"]*admin | awk -F\"kubeconfig\":\" '{print $2}' > config && sed -i 's/\\n/\n/g' config
fi

mkdir -p /tmp/civo-outline
cd /tmp/civo-outline

rm -rf cert/ config kubernates-outline-civo/  &> /dev/null

git clone --quiet  https://github.com/rejahrehim/kubernates-outline-civo.git

export CERTIFICATE_NAME=shadowbox-selfsigned-dev
export SB_CERTIFICATE_FILE="cert/${CERTIFICATE_NAME}.crt"
export SB_PRIVATE_KEY_FILE="cert/${CERTIFICATE_NAME}.key"
mkdir cert
declare -a openssl_req_flags=(
  -x509
  -nodes
  -days 36500
  -newkey rsa:2048
  -subj '/CN=localhost'
  -keyout "${SB_PRIVATE_KEY_FILE}"
  -out "${SB_CERTIFICATE_FILE}"
)
openssl req "${openssl_req_flags[@]}" > /dev/null 
kubectl create namespace outline --kubeconfig config
kubectl create secret tls shadowbox-tls -n outline --key ${SB_PRIVATE_KEY_FILE} --cert ${SB_CERTIFICATE_FILE} --kubeconfig config

kubectl apply -f kubernates-outline-civo/pv.yaml --kubeconfig config
kubectl apply -f kubernates-outline-civo/pvc.yaml --kubeconfig config
kubectl apply -f kubernates-outline-civo/nfs-deply.yaml --kubeconfig config

lbIP=`kubectl get svc traefik -n kube-system --kubeconfig config  -o jsonpath="{['status']['loadBalancer']['ingress'][0]['ip']}"`
nfsServerIp=`kubectl get svc nfs-server --kubeconfig config  -o jsonpath="{['spec']['clusterIP']}"`

sed -i s/xxx.xxx.xxx.xxx/$nfsServerIp/g kubernates-outline-civo/nfs-pv.yaml

kubectl apply -f kubernates-outline-civo/nfs-pv.yaml --kubeconfig config

sed -i s/xxx.xxx.xxx.xxx/$lbIP/g kubernates-outline-civo/vpn-ser.yaml
sed -i s/xxx.xxx.xxx.xxx/$lbIP/g kubernates-outline-civo/outline-pod.yaml


kubectl apply -f kubernates-outline-civo/vpn-ser.yaml --kubeconfig config
kubectl apply -f kubernates-outline-civo/outline-pod.yaml --kubeconfig config

export SHA=$(openssl x509 -noout -fingerprint  -sha256 -inform pem -in ${SB_CERTIFICATE_FILE} | sed "s/://g" | sed 's/.*=//')


echo \{\"apiUrl\":\"https://$lbIP:8081/TestApiPrefix\",\"certSha256\":\"${SHA}\"\}


