#!/bin/bash
PASSWD=Aa792548841..
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


mkdir -p /data/work
ssh master1 "mkdir -p /etc/etcd && mkdir -p /etc/etcd/ssl" &>>/dev/null
ssh master2 "mkdir -p /etc/etcd && mkdir -p /etc/etcd/ssl" &>>/dev/null
ssh master3 "mkdir -p /etc/etcd && mkdir -p /etc/etcd/ssl" &>>/dev/null
check "创建生成工作目录"

cd /data/work
wget https://dl.k8s.io/v1.20.7/kubernetes-server-linux-amd64.tar.gz &>>/dev/null
tar xvf  kubernetes-server-linux-amd64.tar.gz  &>>/dev/null
cd /data/work/kubernetes/server/bin/
cp kube-apiserver kubectl kube-scheduler kube-controller-manager /usr/local/bin/ &>>/dev/null
scp kube-apiserver kubectl kube-scheduler kube-controller-manager master2:/usr/local/bin/ &>>/dev/null
scp kube-apiserver kubectl kube-scheduler kube-controller-manager master3:/usr/local/bin/ &>>/dev/null
check "下载kubectl、kube-apiserver、kube-scheduler、kube-controller-manager二进制安装包"

expect <<END &>>/dev/null
set time 30
spawn scp 192.168.88.88:/root/script/binary_install_k8s/software_config/cfssl/* /data/work 
expect {
"*yes/no" { send "yes\r"; exp_continue }
"*password:" { send "$PASSWD\r" }
}
expect eof
END
check "从主机上安装证书所需文件"

chmod +x /data/work/*
mv /data/work/cfssl_linux-amd64 /usr/local/bin/cfssl &>>/dev/null
mv /data/work/cfssl-certinfo_linux-amd64 /usr/bin/cfssl-certinfo &>>/dev/null
mv /data/work/cfssljson_linux-amd64 /usr/local/bin/cfssljson &>>/dev/null
check "配置cfssl命令"

cat > /data/work/ca-csr.json<<END
{
  "CN": "kubernetes",
  "key": {
      "algo": "rsa",
      "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "HeNan",
      "L": "ZhengZhou",
      "O": "k8s",
      "OU": "system"
    }
  ],
  "ca": {
          "expiry": "87600h"
  }
}
END
check "配置ca证书请求文件"

cat > /data/work/ca-config.json<<END
{
  "signing": {
      "default": {
          "expiry": "87600h"
        },
      "profiles": {
          "kubernetes": {
              "usages": [
                  "signing",
                  "key encipherment",
                  "server auth",
                  "client auth"
              ],
              "expiry": "87600h"
          }
      }
  }
}
END
check "配置ca证书配置文件"

cd /data/work
cfssl gencert -initca ca-csr.json  | cfssljson -bare ca &>>/dev/null
check "生成ca证书pem与key"

cat > /data/work/etcd-csr.json<<END
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "192.168.106.11",
    "192.168.106.12",
    "192.168.106.13",
    "192.168.106.14",
    "192.168.106.15",
    "192.168.106.16",
    "192.168.106.100"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [{
    "C": "CN",
    "ST": "HeNan",
    "L": "ZhengZhou",
    "O": "k8s",
    "OU": "system"
  }]
} 
END
cd /data/work/
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes etcd-csr.json | cfssljson  -bare etcd &>>/dev/null
check "生成etcd证书"

cp /data/work/ca*.pem /etc/etcd/ssl/
cp etcd*.pem /etc/etcd/ssl/
scp  /etc/etcd/ssl/*  master2:/etc/etcd/ssl/ &>>/dev/null
scp  /etc/etcd/ssl/*  master3:/etc/etcd/ssl/ &>>/dev/null
check "拷贝证书到指定位置、拷贝证书到master节点的指定位置"

cat > /data/work/kube-apiserver-csr.json <<END
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "192.168.106.11",
    "192.168.106.12",
    "192.168.106.13",
    "192.168.106.21",
    "192.168.106.22",
    "192.168.106.23",
    "192.168.106.100",
    "10.255.0.1",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "HeNan",
      "L": "ZhengZhou",
      "O": "k8s",
      "OU": "system"
    }
  ]
}
END
check "生成kube-apiserver的证书请求文件"

cd /data/work
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-apiserver-csr.json | cfssljson -bare kube-apiserver &>>/dev/null
check "生成kube-apiserver证书"

ssh master1 "mkdir -p /etc/kubernetes/ssl" &>>/dev/null
ssh master2 "mkdir -p /etc/kubernetes/ssl" &>>/dev/null
ssh master3 "mkdir -p /etc/kubernetes/ssl" &>>/dev/null
cp /data/work/ca*.pem /etc/kubernetes/ssl &>>/dev/null
cp /data/work/kube-apiserver*.pem /etc/kubernetes/ssl &>>/dev/null
scp /etc/kubernetes/ssl/* master2:/etc/kubernetes/ssl/ &>>/dev/null
scp /etc/kubernetes/ssl/* master3:/etc/kubernetes/ssl/ &>>/dev/null
check "拷贝kube-apiserver证书到指定文件夹及拷贝到其他master节点"

cat > /data/work/admin-csr.json <<END
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "HeNan",
      "L": "ZhengZhou",
      "O": "system:masters",             
      "OU": "system"
    }
  ]
}
END
check "创建kubectl证书请求文件"

cd /data/work
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare admin &>>/dev/null
check "创建kubectl证书文件"

cp /data/work/admin*.pem /etc/kubernetes/ssl/ &>>/dev/null
scp /etc/kubernetes/ssl/* master2:/etc/kubernetes/ssl/ &>>/dev/null
scp /etc/kubernetes/ssl/* master3:/etc/kubernetes/ssl/ &>>/dev/null
check "拷贝kubectl证书到指定文件夹及拷贝到其他master节点"

cd /data/work
kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true --server=https://192.168.106.11:6443 --kubeconfig=kube.config &>>/dev/null
kubectl config set-credentials admin --client-certificate=admin.pem --client-key=admin-key.pem --embed-certs=true --kubeconfig=kube.config &>>/dev/null
kubectl config set-context kubernetes --cluster=kubernetes --user=admin --kubeconfig=kube.config &>>/dev/null
kubectl config use-context kubernetes --kubeconfig=kube.config &>>/dev/null
mkdir ~/.kube -p
cp /data/work/kube.config ~/.kube/config
check "创建kubeconfig配置文件"


ssh master2 "mkdir /root/.kube/"
ssh master3 "mkdir /root/.kube/"
scp /root/.kube/config master2:~/.kube/  
scp /root/.kube/config master3:~/.kube/
check "拷贝证书到master2与master3节点"

cat > /data/work/kube-controller-manager-csr.json <<END 
{
    "CN": "system:kube-controller-manager",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "hosts": [
      "127.0.0.1",
      "192.168.106.11",
      "192.168.106.12",
      "192.168.106.13",
      "192.168.106.100"
    ],
    "names": [
      {
        "C": "CN",
        "ST": "HeNan",
        "L": "ZhengZhou",
        "O": "system:kube-controller-manager",
        "OU": "system"
      }
    ]
}
END
check "生成kube-controller-manager证书请求文件"

cd /data/work
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager  &>>/dev/null
check "生成kube-controller-manager证书"

cd /data/work
kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true --server=https://192.168.106.11:6443 --kubeconfig=kube-controller-manager.kubeconfig &>>/dev/null
kubectl config set-credentials system:kube-controller-manager --client-certificate=kube-controller-manager.pem --client-key=kube-controller-manager-key.pem --embed-certs=true --kubeconfig=kube-controller-manager.kubeconfig &>>/dev/null
kubectl config set-context system:kube-controller-manager --cluster=kubernetes --user=system:kube-controller-manager --kubeconfig=kube-controller-manager.kubeconfig &>>/dev/null
kubectl config use-context system:kube-controller-manager --kubeconfig=kube-controller-manager.kubeconfig &>>/dev/null
check "创建kube-controller-manager的kubeconfig"

cp /data/work/kube-controller-manager.kubeconfig /etc/kubernetes/ &>>/dev/null
cp /data/work/kube-controller-manager*.pem /etc/kubernetes/ssl/ &>>/dev/null
scp /data/work/kube-controller-manager*.pem master2:/etc/kubernetes/ssl/  &>>/dev/null
scp /data/work/kube-controller-manager*.pem master3:/etc/kubernetes/ssl/ &>>/dev/null
scp /data/work/kube-controller-manager.kubeconfig master2:/etc/kubernetes/ &>>/dev/null
scp /data/work/kube-controller-manager.kubeconfig master3:/etc/kubernetes/ &>>/dev/null
check "拷贝kube-controller-manager证书到指定文件夹及拷贝到其他master节点"

cat > /data/work/kube-scheduler-csr.json <<END
{
    "CN": "system:kube-scheduler",
    "hosts": [
      "127.0.0.1",
      "192.168.106.11",
      "192.168.106.12",
      "192.168.106.13",
      "192.168.106.100"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
      {
        "C": "CN",
        "ST": "HeNan",
        "L": "ZhengZhou",
        "O": "system:kube-scheduler",
        "OU": "system"
      }
    ]
}
END
check "创建kube-scheduler证书请求文件"

cd /data/work
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-scheduler-csr.json | cfssljson -bare kube-scheduler &>>/dev/null
check "生成kube-scheduler证书"

kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true --server=https://192.168.106.11:6443 --kubeconfig=kube-scheduler.kubeconfig &>>/dev/null
kubectl config set-credentials system:kube-scheduler --client-certificate=kube-scheduler.pem --client-key=kube-scheduler-key.pem --embed-certs=true --kubeconfig=kube-scheduler.kubeconfig &>>/dev/null
kubectl config set-context system:kube-scheduler --cluster=kubernetes --user=system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig &>>/dev/null
kubectl config use-context system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig &>>/dev/null
check "创建kube-scheduler的kubeconfig"

cp /data/work/kube-scheduler.kubeconfig /etc/kubernetes/ &>>/dev/null
scp /data/work/kube-scheduler.kubeconfig master2:/etc/kubernetes/ &>>/dev/null
scp /data/work/kube-scheduler.kubeconfig master3:/etc/kubernetes/ &>>/dev/null
cp /data/work/kube-scheduler*.pem /etc/kubernetes/ssl/ &>>/dev/null
scp /data/work/kube-scheduler*.pem master2:/etc/kubernetes/ssl/ &>>/dev/null
scp /data/work/kube-scheduler*.pem master3:/etc/kubernetes/ssl/ &>>/dev/null
check "拷贝kube-scheduler证书到指定文件夹及拷贝到其他master节点"

cat > /etc/kubernetes/token.csv <<END
$(head -c 16 /dev/urandom | od -An -t x | tr -d ' '),kubelet-bootstrap,10001,"system:kubelet-bootstrap"
END
scp /etc/kubernetes/token.csv master2:/etc/kubernetes/ &>>/dev/null
scp /etc/kubernetes/token.csv master3:/etc/kubernetes/ &>>/dev/null
check "创建token.csv拷贝到mster2与master3节点"

cd /data/work/
BOOTSTRAP_TOKEN=$(awk -F "," '{print $1}' /etc/kubernetes/token.csv)
kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true --server=https://192.168.106.11:6443 --kubeconfig=kubelet-bootstrap.kubeconfig &>>/dev/null
kubectl config set-credentials kubelet-bootstrap --token=${BOOTSTRAP_TOKEN} --kubeconfig=kubelet-bootstrap.kubeconfig &>>/dev/null
kubectl config set-context default --cluster=kubernetes --user=kubelet-bootstrap --kubeconfig=kubelet-bootstrap.kubeconfig &>>/dev/null
kubectl config use-context default --kubeconfig=kubelet-bootstrap.kubeconfig &>>/dev/null
check "创建kubelet-bootstrap.kubeconfig"

ssh node1 "mkdir -p /etc/kubernetes/ssl" &>>/dev/null
ssh node2 "mkdir -p /etc/kubernetes/ssl" &>>/dev/null
ssh node3 "mkdir -p /etc/kubernetes/ssl" &>>/dev/null
scp /data/work/kubelet-bootstrap.kubeconfig node1:/etc/kubernetes/ &>>/dev/null
scp /data/work/kubelet-bootstrap.kubeconfig node2:/etc/kubernetes/ &>>/dev/null
scp /data/work/kubelet-bootstrap.kubeconfig node3:/etc/kubernetes/ &>>/dev/null
scp /data/work/ca.pem node1:/etc/kubernetes/ssl/  &>>/dev/null
scp /data/work/ca.pem node2:/etc/kubernetes/ssl/   &>>/dev/null
scp /data/work/ca.pem node3:/etc/kubernetes/ssl/ &>>/dev/null
check "向node节点上拷贝证书文件"

cat > /data/work/kube-proxy-csr.json <<END
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "HeNan",
      "L": "ZhengZhou",
      "O": "k8s",
      "OU": "system"
    }
      ]
}
END
check "创建kube-proxy证书请求文件"

cd /data/work/
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy &>>/dev/null
check "生成kube-proxy证书"

kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true --server=https://192.168.106.11:6443 --kubeconfig=kube-proxy.kubeconfig &>>/dev/null
kubectl config set-credentials kube-proxy --client-certificate=kube-proxy.pem --client-key=kube-proxy-key.pem --embed-certs=true --kubeconfig=kube-proxy.kubeconfig &>>/dev/null
kubectl config set-context default --cluster=kubernetes --user=kube-proxy --kubeconfig=kube-proxy.kubeconfig &>>/dev/null
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig &>>/dev/null
check "创建kube-proxy的kubeconfig"

scp /data/work/kube-proxy.kubeconfig node1:/etc/kubernetes/ &>>/dev/null
scp /data/work/kube-proxy.kubeconfig node2:/etc/kubernetes/ &>>/dev/null
scp /data/work/kube-proxy.kubeconfig node3:/etc/kubernetes/ &>>/dev/null
check "拷贝kube-proxy的kubeconfig"
