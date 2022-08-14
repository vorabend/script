#!/bin/bash
function check ()
{
if [ $? == 0 ]
  then 
    echo -e "\x1b[32;1m $1====> SUCCESS \x1b[0m"
  else 
    echo -e "\x1b[31;1m $1====> FAILE \x1b[0m"
  exit 1
fi
}

#部署etcd服务（master）
function deploy_etcd ()
{
mkdir -p /etc/etcd && mkdir -p /etc/etcd/ssl
check "创建ectd工作目录"

IP_LOCAL=`ip  a s| grep eth0 | grep inet | awk {'print $2'}|awk -F "/" {'print $1'}`
HOST_NAME_NUM=`cat /etc/hostname | awk -F "r" {'print $2'}`
mkdir -p /var/lib/etcd/default.etcd
cat > /etc/etcd/etcd.conf<<END
#[Member]
ETCD_NAME="etcd$HOST_NAME_NUM"
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="https://$IP_LOCAL:2380"
ETCD_LISTEN_CLIENT_URLS="https://$IP_LOCAL:2379,http://127.0.0.1:2379"
#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://$IP_LOCAL:2380"
ETCD_ADVERTISE_CLIENT_URLS="https://$IP_LOCAL:2379"
ETCD_INITIAL_CLUSTER="etcd1=https://192.168.106.11:2380,etcd2=https://192.168.106.12:2380,etcd3=https://192.168.106.13:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_INITIAL_CLUSTER_STATE="new"
END
check "创建etcd配置文件"

cat > /usr/lib/systemd/system/etcd.service<<END
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
 
[Service]
Type=notify
EnvironmentFile=-/etc/etcd/etcd.conf
WorkingDirectory=/var/lib/etcd/
ExecStart=/usr/local/bin/etcd \\
  --cert-file=/etc/etcd/ssl/etcd.pem \\
  --key-file=/etc/etcd/ssl/etcd-key.pem \\
  --trusted-ca-file=/etc/etcd/ssl/ca.pem \\
  --peer-cert-file=/etc/etcd/ssl/etcd.pem \\
  --peer-key-file=/etc/etcd/ssl/etcd-key.pem \\
  --peer-trusted-ca-file=/etc/etcd/ssl/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
 
[Install]
WantedBy=multi-user.target
END
check "创建etcd启动文件"

systemctl daemon-reload
systemctl enable etcd --now 
check "启动etcd服务"
}

#部署api-server（master）
function deploy_apiserver ()
{
mkdir -p /etc/kubernetes/ 
mkdir -p /etc/kubernetes/ssl
mkdir /var/log/kubernetes
check "创建kubernetes目录"

cat  > /etc/kubernetes/kube-apiserver.conf <<END
KUBE_APISERVER_OPTS="--enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --anonymous-auth=false \\
  --bind-address=`ip  a s| grep eth0 | grep inet | awk {'print $2'}|awk -F "/" {'print $1'}` \\
  --secure-port=6443 \\
  --advertise-address=`ip  a s| grep eth0 | grep inet | awk {'print $2'}|awk -F "/" {'print $1'}` \\
  --insecure-port=0 \\
  --authorization-mode=Node,RBAC \\
  --runtime-config=api/all=true \\
  --enable-bootstrap-token-auth \\
  --service-cluster-ip-range=10.255.0.0/16 \\
  --token-auth-file=/etc/kubernetes/token.csv \\
  --service-node-port-range=30000-50000 \\
  --tls-cert-file=/etc/kubernetes/ssl/kube-apiserver.pem  \\
  --tls-private-key-file=/etc/kubernetes/ssl/kube-apiserver-key.pem \\
  --client-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --kubelet-client-certificate=/etc/kubernetes/ssl/kube-apiserver.pem \\
  --kubelet-client-key=/etc/kubernetes/ssl/kube-apiserver-key.pem \\
  --service-account-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --service-account-signing-key-file=/etc/kubernetes/ssl/ca-key.pem  \\
  --service-account-issuer=https://kubernetes.default.svc.cluster.local \\
  --etcd-cafile=/etc/etcd/ssl/ca.pem \\
  --etcd-certfile=/etc/etcd/ssl/etcd.pem \\
  --etcd-keyfile=/etc/etcd/ssl/etcd-key.pem \\
  --etcd-servers=https://192.168.106.11:2379,https://192.168.106.12:2379,https://192.168.106.13:2379 \\
  --enable-swagger-ui=true \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/kube-apiserver-audit.log \\
  --event-ttl=1h \\
  --alsologtostderr=true \\
  --logtostderr=false \\
  --log-dir=/var/log/kubernetes \\
  --v=4"
END
check "创建kube-apiserver配置文件"

cat > /usr/lib/systemd/system/kube-apiserver.service <<END
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=etcd.service
Wants=etcd.service
 
[Service]
EnvironmentFile=-/etc/kubernetes/kube-apiserver.conf
ExecStart=/usr/local/bin/kube-apiserver \$KUBE_APISERVER_OPTS
Restart=on-failure
RestartSec=5
Type=notify
LimitNOFILE=65536
 
[Install]
WantedBy=multi-user.target
END
check "创建kube-apiserver启动文件"

systemctl daemon-reload && systemctl enable kube-apiserver --now && systemctl status kube-apiserver
check "启动api-server服务"
}

#部署kubectl组件（master）
function deploy_kubectl ()
{
if [  `hostname` == master1 ]
then 
cd /data/work
kubectl create clusterrolebinding kube-apiserver:kubelet-apis --clusterrole=system:kubelet-api-admin --user kubernetes
kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap
else
echo 666
fi &>>/dev/null
check "授权kubebernetes证书访问kubelet-api的权限"

yum install -y bash-completion &>>/dev/null
source /usr/share/bash-completion/bash_completion
source <(kubectl completion bash)
kubectl completion bash > ~/.kube/completion.bash.inc
source '/root/.kube/completion.bash.inc'
source $HOME/.bash_profile
echo "source '/root/.kube/completion.bash.inc'" >> /etc/bashrc
check 	"配置kubectl子命令补全"
}

#部署kube-controller--manager组件（master）
function deploy_controller_manager ()
{
cat > /etc/kubernetes/kube-controller-manager.conf <<END
KUBE_CONTROLLER_MANAGER_OPTS="--port=0 \\
  --secure-port=10252 \\
  --bind-address=127.0.0.1 \\
  --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \\
  --service-cluster-ip-range=10.255.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem \\
  --cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --allocate-node-cidrs=true \\
  --cluster-cidr=10.0.0.0/16 \\
  --experimental-cluster-signing-duration=87600h \\
  --root-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --service-account-private-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --leader-elect=true \\
  --feature-gates=RotateKubeletServerCertificate=true \\
  --controllers=*,bootstrapsigner,tokencleaner \\
  --horizontal-pod-autoscaler-use-rest-clients=true \\
  --horizontal-pod-autoscaler-sync-period=10s \\
  --tls-cert-file=/etc/kubernetes/ssl/kube-controller-manager.pem \\
  --tls-private-key-file=/etc/kubernetes/ssl/kube-controller-manager-key.pem \\
  --use-service-account-credentials=true \\
  --alsologtostderr=true \\
  --logtostderr=false \\
  --log-dir=/var/log/kubernetes \\
  --v=2"
END
check "创建kube-controller-manager.conf配置文件"

cat > /usr/lib/systemd/system/kube-controller-manager.service <<END
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes
[Service]
EnvironmentFile=-/etc/kubernetes/kube-controller-manager.conf
ExecStart=/usr/local/bin/kube-controller-manager \$KUBE_CONTROLLER_MANAGER_OPTS
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
END
check "创建kube-controller-manager启动文件"

systemctl daemon-reload && systemctl enable kube-controller-manager --now && systemctl status kube-controller-manager 
check "启动kube-controller-manager服务"
}

#部署kube-scheduler组件（matser）
function deploy_scheduler ()
{
cat > /etc/kubernetes/kube-scheduler.conf <<END
KUBE_SCHEDULER_OPTS="--address=127.0.0.1 \\
--kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \\
--leader-elect=true \\
--alsologtostderr=true \\
--logtostderr=false \\
--log-dir=/var/log/kubernetes \\
--v=2"
END
check "创建配置文件kube-scheduler.conf"

cat > /usr/lib/systemd/system/kube-scheduler.service <<END
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes
 
[Service]
EnvironmentFile=-/etc/kubernetes/kube-scheduler.conf
ExecStart=/usr/local/bin/kube-scheduler \$KUBE_SCHEDULER_OPTS
Restart=on-failure
RestartSec=5
 
[Install]
WantedBy=multi-user.target
END
check "创建kube-scheduler的启动文件"

systemctl daemon-reload && systemctl enable kube-scheduler --now && systemctl status  kube-scheduler &>>/dev/null
check "启动kube-scheduler服务"
}

#部署kubelet服务（node）
function deploy_kubelet ()
{
mkdir /var/lib/kubelet
wget https://dl.k8s.io/v1.20.7/kubernetes-server-linux-amd64.tar.gz &>>/dev/null
tar -xf kubernetes-server-linux-amd64.tar.gz
cd kubernetes/server/bin/
mv kube-proxy kubelet /usr/local/bin/  
cat > /etc/kubernetes/kubelet.json <<END
{
  "kind": "KubeletConfiguration",
  "apiVersion": "kubelet.config.k8s.io/v1beta1",
  "authentication": {
    "x509": {
      "clientCAFile": "/etc/kubernetes/ssl/ca.pem"
    },
    "webhook": {
      "enabled": true,
      "cacheTTL": "2m0s"
    },
    "anonymous": {
      "enabled": false
    }
  },
  "authorization": {
    "mode": "Webhook",
    "webhook": {
      "cacheAuthorizedTTL": "5m0s",
      "cacheUnauthorizedTTL": "30s"
    }
  },
  "address": "`ip a s | grep eth0 | grep inet | awk {'print $2'} | awk -F "/" {'print $1'}`",
  "port": 10250,
  "readOnlyPort": 10255,
  "cgroupDriver": "systemd",
  "hairpinMode": "promiscuous-bridge",
  "serializeImagePulls": false,
  "featureGates": {
    "RotateKubeletClientCertificate": true,
    "RotateKubeletServerCertificate": true
  },
  "clusterDomain": "cluster.local.",
  "clusterDNS": ["10.255.0.2"]
}
END
check "创建配置文件kubelet.json"

cat > /usr/lib/systemd/system/kubelet.service <<END
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=docker.service
Requires=docker.service
[Service]
WorkingDirectory=/var/lib/kubelet
ExecStart=/usr/local/bin/kubelet \\
  --bootstrap-kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig \\
  --cert-dir=/etc/kubernetes/ssl \\
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \\
  --config=/etc/kubernetes/kubelet.json \\
  --network-plugin=cni \\
  --pod-infra-container-image=k8s.gcr.io/pause:3.2 \\
  --alsologtostderr=true \\
  --logtostderr=false \\
  --log-dir=/var/log/kubernetes \\
  --v=2
Restart=on-failure
RestartSec=5
 
[Install]
WantedBy=multi-user.target
END
check "创建服务kubelet的启动文件"

systemctl daemon-reload && systemctl enable kubelet --now && systemctl status  kubelet &>>/dev/null
check "启动服务kubelet"
}

#部署kube-proxy组件(node)
function deploy_proxy ()
{
expect <<EOF &>>/dev/null
    set timeout 10 
    spawn scp 192.168.88.88:/root/software/pause-cordns.tar.gz .
    expect { 
        "(yes/no)?" { send "yes\n";exp_continue } 
        "password:" { send "Aa792548841..\n";exp_continue }
    } 
EOF
docker load -i pause-cordns.tar.gz &>>/dev/null
check "导入docker镜像"

cat > /etc/kubernetes/kube-proxy.yaml <<END
apiVersion: kubeproxy.config.k8s.io/v1alpha1
bindAddress: `ip a s | grep eth0 | grep inet | awk {'print $2'} | awk -F "/" {'print $1'}`
clientConnection:
  kubeconfig: /etc/kubernetes/kube-proxy.kubeconfig
clusterCIDR: 192.168.106.0/24
healthzBindAddress: `ip a s | grep eth0 | grep inet | awk {'print $2'} | awk -F "/" {'print $1'}`:10256
kind: KubeProxyConfiguration
metricsBindAddress: `ip a s | grep eth0 | grep inet | awk {'print $2'} | awk -F "/" {'print $1'}`:10249
mode: "ipvs"
END
check "创建kube-proxy配置文件"

mkdir -p /var/lib/kube-proxy
cat > /usr/lib/systemd/system/kube-proxy.service  <<END
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/kubernetes/kubernetes
After=network.target
 
[Service]
WorkingDirectory=/var/lib/kube-proxy
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/etc/kubernetes/kube-proxy.yaml \\
  --alsologtostderr=true \\
  --logtostderr=false \\
  --log-dir=/var/log/kubernetes \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
 
[Install]
WantedBy=multi-user.target
END
check "创建kube-proxy服务启动文件"

systemctl daemon-reload && systemctl enable kube-proxy --now && systemctl status kube-proxy &>>/dev/null
check "启动kube-proxy服务"
}

#部署calico组件(node)
function deploy_calico ()
{
expect <<EOF &>>/dev/null
    set timeout 10 
    spawn scp 192.168.88.88:/root/software/*.tar.gz .
    expect { 
        "(yes/no)?" { send "yes\n";exp_continue } 
        "password:" { send "Aa792548841..\n";exp_continue }
    } 
EOF
docker load -i calico.tar.gz
docker load -i pause-cordns.tar.gz 
check "导入docker calico镜像"
}
deploy_kubelet
deploy_proxy
deploy_calico
grep -r 6443 /etc/kubernetes/ | awk -F ":" {'print $1'} | xargs sed -i  "s/192.168.106.11:6443/192.168.106.100:16443/" systemctl restart kubelet kube-proxy && systemctl status  kubelet kube-proxy
