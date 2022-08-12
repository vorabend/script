#!/bin/bash
echo -e "\x1b[32;1m######## openssh update to openssh9.0 #######\x1b[0m"

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

wget https://mirrors.aliyun.com/pub/OpenBSD/OpenSSH/portable/openssh-9.0p1.tar.gz?spm=a2c6h.25603864.0.0.686840ad2Awo5a &>>/dev/null
check "Download openssh9.0"

mv openssh-9.0p1.tar.gz\?spm\=a2c6h.25603864.0.0.686840ad2Awo5a openssh-9.0p1.tar.gz
check "rename openssh file"

yum group install "Development Tools" -y &>>/dev/null
check "install Development Tools"

yum install openssl-devel -y &>>/dev/null
check "install openssl-devel"

tar -xf  openssh-9.0p1.tar.gz
check "tar file"

cd openssh-9.0p1/
check "cd openssh file"

./configure &>>/dev/null
check "check install"

make  &>>/dev/null
check "make"

make install &>>/dev/null
check "make install"

systemctl disable sshd --now &>>/dev/null
check "stop sshd"

sed -i "s/^#PermitRoot.*/PermitRootLogin yes/" /usr/local/etc/sshd_config &>>/dev/null
check "modify sshd config file"

cat > /usr/lib/systemd/system/sshd90.service<<END
[Unit]
Description=OpenSSH server daemon
Documentation=man:sshd(8) man:sshd_config(5)
After=network.target sshd-keygen.target
Wants=sshd-keygen.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/sshd 
#ExecReload=/bin/kill 
KillMode=process
Restart=on-failure
RestartSec=42s

[Install]
WantedBy=multi-user.target
END
check "touch sshd90.service"

systemctl enable sshd90 --now &>>/dev/null
check "start sshd90"
