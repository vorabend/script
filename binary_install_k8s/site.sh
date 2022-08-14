#!/bin/bash
for i in 11 12 13 21 22 23
do
expect <<EOF &>>/dev/null
    set timeout 10 
    spawn scp -r /root/script/binary_install_k8s 192.168.106.$i:~
    expect { 
        "(yes/no)?" { send "yes\n";exp_continue } 
        "password:" { send "1\n";exp_continue }
    } 
EOF
done

for i in 11 12 13 21 22 23 
do 
sshpass -p1 ssh 192.168.106.$i "bash binary_install_k8s/env.sh" 
done

sshpass -p1 ssh 192.168.106.11 "bash binary_install_k8s/set-cer.sh" 

for i in 11 12 13 
do
sshpass -p1 ssh 192.168.106.$i "bash binary_install_k8s/deploy_module_master.sh"
done

for i in 21 22 23 
do
	sshpass -p1 ssh 192.168.106.$i "bash binary_install_k8s/deploy_module_node.sh"
done

sshpass -p1 ssh 192.168.106.11 "kubectl apply -f binary_install_k8s/software_config/coredns.yaml"
sshpass -p1 ssh 192.168.106.11 "kubectl apply -f binary_install_k8s/software_config/calico.yaml"
sshpass -p1 ssh 192.168.106.11 "bash binary_install_k8s/deploy_keepalived_nginx.sh"
sshpass -p1 ssh 192.168.106.12 "bash binary_install_k8s/deploy_keepalived_nginx.sh"

