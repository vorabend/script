#!/bin/bash
rm -rf /etc/yum.repos.d/*
cat > a.repo<<END 
[AppStream]
name=AppStream
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos/8-stream/AppStream/x86_64/os/
gpgcheck=0
enable=1

[BaseOS]
name=BaseOS
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos/8-stream/BaseOS/x86_64/os/
gpgcheck=0
enable=1

[epel]
name=epel
baseurl=https://mirrors.tuna.tsinghua.edu.cn/epel/8/Everything/x86_64/
gpgcheck=0
enable=1
END
yum repolist
