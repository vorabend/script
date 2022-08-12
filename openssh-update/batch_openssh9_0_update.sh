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

for i in 14 15 
do 
sshpass -p1 ssh-copy-id root@192.168.102.$i &>>/dev/null
check "check no pass login"

scp openssh9_0.sh root@192.168.102.$i:~
check "check file is true"
done

for i in 14 15 
do 
ssh root@192.168.102.$i "bash /root/openssh9_0.sh" &
done
wait


