#!/bin/bash

export KUBEVIRT_NS=kube-system
export CDI_NS=golden-images
export IP=`ip -o -4 a | tr -s ' ' | grep -v -e ' lo[0-9:]*.*$' | cut -d     ' ' -f 4 | head -1 | sed 's#/.*##'`
DATA_DIR="`pwd`/_data"
#
# Cluster
#
mkdir -p $DATA_DIR
oc cluster up --service-catalog --public-hostname="$IP" --routing-suffix="$IP.nip.io" --host-data-dir=$DATA_DIR --use-existing-config=true

oc login -u system:admin --insecure-skip-tls-verify=true https://$IP:8443

#
# Storage
#
oc get serviceaccount storage-demo -n $KUBEVIRT_NS || \
	oc create serviceaccount storage-demo -n $KUBEVIRT_NS
oc adm policy add-scc-to-user privileged system:serviceaccount:$KUBEVIRT_NS:storage-demo
oc new-project $CDI_NS
oc get clusterrolebinding c-$CDI_NS-default || \                    
	oc create clusterrolebinding c-$CDI_NS-default --clusterrole=cluster-admin --serviceaccount=$CDI_NS:default 

rm _out/*
j2 -f env manifests/storage-demo.yml.j2 > _out/storage-demo.yml
j2 -f env manifests/cdi-resourcequota.yml.j2 > _out/cdi-resourcequota.yml
j2 -f env manifests/cdi-controller-deployment.yml.j2 > _out/cdi-controller-deployment.yml

oc create -f _out/storage-demo.yml
oc create -f _out/cdi-resourcequota.yml
oc create -f _out/cdi-controller-deployment.yml

#
# Kubevirt
#
oc adm policy add-scc-to-user privileged -z kubevirt-privileged -n $KUBEVIRT_NS
oc adm policy add-scc-to-user privileged -z kubevirt-controller -n $KUBEVIRT_NS
oc adm policy add-scc-to-user privileged -z kubevirt-infra -n $KUBEVIRT_NS
oc create -f manifests/kubevirt.yaml

#                                                                               
# Misc                                                                          
#                                                                               
oc adm policy add-cluster-role-to-user cluster-admin developer                  
oc patch -n openshift-web-console  deploy webconsole -p '{"spec":{"template":{"spec":{"containers":[{"name": "webconsole","image": "mutism/origin-web-console:demo"}]}}}}'  

#
# ASB
#
./service-catalog/run_latest_build.sh                                           
oc delete -f service-catalog/broker-config.yml                                  
oc create -f service-catalog/broker-config.yml                                  
oc delete pod -n ansible-service-broker -l app=ansible-service-broker           

