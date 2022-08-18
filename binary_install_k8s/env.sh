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

cat > /etc/hosts<<END
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
192.168.106.11 master1
192.168.106.12 master2
192.168.106.13 master3
192.168.106.21 node1
192.168.106.22 node2
192.168.106.23 node3
END
check "配置主机hosts文件"

yum install -y yum-utils device-mapper-persistent-data lvm2 wget net-tools nfs-utils lrzsz gcc gcc-c++ make cmake libxml2-devel openssl-devel curl curl-devel unzip sudo ntp libaio-devel  vim ncurses-devel autoconf automake zlib-devel  python-devel epel-release openssh-server socat  ipvsadm conntrack ntpdate telnet ipvsadm bash-completion rsync expect &>>/dev/null
check "安装基础软件包"

expect <<EOF &>>/dev/null
    set timeout 10 
    spawn ssh-keygen
    expect { 
        "(/root/.ssh/id_rsa):" { send "\n";exp_continue } 
        "(empty for no passphrase):" { send "\n";exp_continue }
        "again:" { send "\n";exp_continue }
    } 
EOF
check "生成公私匙文件"

for i in master1 master2 master3 node1 node2 node3
do
expect <<EOF &>>/dev/null
    set timeout 10 
    spawn ssh-copy-id $i
    expect { 
        "(yes/no)?" { send "yes\n";exp_continue } 
        "password:" { send "1\n";exp_continue }
    } 
EOF
done
check "配置主机间的免密登录"

swapoff -a &>>/dev/null
sed -i 's/\/dev\/mapper\/centos-swap/#\/dev\/mapper\/centos-swap/' /etc/fstab &>>/dev/null
check "关闭swap分区"

modprobe br_netfilter &>>/dev/null
echo 'modprobe br_netfilter' >> /etc/profile
cat > /etc/sysctl.d/k8s.conf<<END
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
END
sysctl -p /etc/sysctl.d/k8s.conf &>>/dev/null
check "加载br_netfilter内核参数"

systemctl disable firewalld --now &>>/dev/null
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config &>>/dev/null
setenforce 0 &>>/dev/null
sed -i "s/^#ClientAliveInterval.*/ClientAliveInterval 600/" /etc/ssh/sshd_config &>>/dev/null
sed -i "s/^#ClientAliveCountMax.*/ClientAliveCountMax 10/" /etc/ssh/sshd_config &>>/dev/null
systemctl restart sshd &>>/dev/null
check "关闭selinux与firewalld"

yum install -y yum-utils &>>/dev/null
yum-config-manager \
--add-repo \
https://download.docker.com/linux/centos/docker-ce.repo &>>/dev/null
check "配置docker repo源"

yum install chrony -y &>>/dev/null
sed -i 's/^server.*//' /etc/chrony.conf &>>/dev/null
sed -i 's/# Please.*/server  ntp.aliyun.com iburst/' /etc/chrony.conf &>>/dev/null
systemctl enable chronyd --now &>>/dev/null
check "配置时间同步"

cat > /etc/sysconfig/modules/ipvs.modules<<END 
#!/bin/bash
ipvs_modules="ip_vs ip_vs_lc ip_vs_wlc ip_vs_rr ip_vs_wrr ip_vs_lblc ip_vs_lblcr ip_vs_dh ip_vs_sh ip_vs_nq ip_vs_sed ip_vs_ftp nf_conntrack"
for kernel_module in \${ipvs_modules}; do
 /sbin/modinfo -F filename \${kernel_module} > /dev/null 2>&1
 if [ 0 -eq 0 ]; then
 /sbin/modprobe \${kernel_module}
 fi
done
END
bash /etc/sysconfig/modules/ipvs.modules &>>/dev/null
if [ `lsmod | grep ip_vs | wc -l` == 0 ]
  then ?
fi &>>/dev/null
check "开启ipvs"


yum install iptables-services -y &>>/dev/null
systemctl disable iptables --now &>>/dev/null
iptables -F  &>>/dev/null
check "安装iptables"

yum install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y &>>/dev/null
mkdir -p /etc/docker &>>/dev/null
mkdir -p /data/docker &>>/dev/null
IP=`ip  a s| grep eth0 | grep inet | awk {'print $2'}|awk -F "/" {'print $1'} | awk -F "." {'print $4'}` &>>/dev/null
cat > /etc/docker/daemon.json<<END 
{
  "data-root":"/data/docker",
  "registry-mirrors": ["https://oym4jkot.mirror.aliyuncs.com"],
  "insecure-registries":["registry.access.redhat.com","quay.io"],
  "bip":"172.106.$IP.1/24",
  "live-restore":true,
  "exec-opts": ["native.cgroupdriver=systemd"]
}
END
systemctl enable docker --now &>>/dev/null && systemctl status docker &>>/dev/null
check "安装与配置docker"

pvcreate /dev/sdb &>>/dev/null
vgextend centos /dev/sdb &>>/dev/null
lvextend -l +100%FREE /dev/mapper/centos-root &>>/dev/null
xfs_growfs /dev/mapper/centos-root &>>/dev/null
check "进行根分区扩容"

#创建目录
if [ `hostname` == master1 ]
then
mkdir -p /etc/etcd/ssl
mkdir /data/work -p
mkdir -p /var/lib/etcd/default.etcd
mkdir -p /etc/kubernetes/ssl
mkdir /var/log/kubernetes 
mkdir ~/.kube -p
fi

if [ `hostname` == master2 ]
then
mkdir -p /etc/etcd/ssl
mkdir -p /var/lib/etcd/default.etcd
mkdir -p /etc/kubernetes/ssl
mkdir /var/log/kubernetes
mkdir ~/.kube -p
fi

if [ `hostname` == master3 ]
then
mkdir -p /etc/etcd/ssl
mkdir -p /var/lib/etcd/default.etcd
mkdir -p /etc/kubernetes/ssl
mkdir /var/log/kubernetes
mkdir ~/.kube -p
fi

if [[ `hostname` == node? ]]
then
mkdir /etc/kubernetes/ssl -p
mkdir /var/lib/kubelet
mkdir /var/log/kubernetes
mkdir -p /var/lib/kube-proxy
fi
check "创建组件目录"

echo "bash /etc/sysconfig/modules/ipvs.modules" >> /etc/rc.d/rc.local 
chmod u+x /etc/rc.d/rc.local

