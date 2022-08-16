#!/bin/bash
#仅master1与master2执行
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
yum install keepalived nginx nginx-mod-stream -y &>>/dev/null
check "安装keepalived与nginx软件"

cat > /etc/nginx/nginx.conf <<END
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

# 四层负载均衡，为两台Master apiserver组件提供负载均衡
stream {

    log_format  main  '$remote_addr $upstream_addr - [$time_local] $status $upstream_bytes_sent';

    access_log  /var/log/nginx/k8s-access.log  main;

    upstream k8s-apiserver {
       server 192.168.106.11:6443;   # xianchaomaster1 APISERVER IP:PORT
       server 192.168.106.12:6443;   # xianchaomaster2 APISERVER IP:PORT
       server 192.168.106.13:6443;   # xianchaomaster3 APISERVER IP:PORT

    }
    
    server {
       listen 16443; # 由于nginx与master节点复用，这个监听端口不能是6443，否则会冲突
       proxy_pass k8s-apiserver;
    }
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    server {
        listen       80 default_server;
        server_name  _;

        location / {
        }
    }
}
END
check "编写nginx配置文件"

systemctl enable nginx --now && systemctl status nginx 
check "启动nginx服务"

if [  `hostname` == master1 ]
then
cat > /etc/keepalived/keepalived.conf<<END
global_defs { 
   notification_email { 
     acassen@firewall.loc 
     failover@firewall.loc 
     sysadmin@firewall.loc 
   } 
   notification_email_from Alexandre.Cassen@firewall.loc  
   smtp_server 127.0.0.1 
   smtp_connect_timeout 30 
   router_id NGINX_MASTER
} 

vrrp_script check_nginx {
    script "/etc/keepalived/check_nginx.sh"
}

vrrp_instance VI_1 { 
    state MASTER 
    interface eth0  # 修改为实际网卡名
    virtual_router_id 51 # VRRP 路由 ID实例，每个实例是唯一的 
    priority 100    # 优先级，备服务器设置 90 
    advert_int 1    # 指定VRRP 心跳包通告间隔时间，默认1秒 
    authentication { 
        auth_type PASS      
        auth_pass 1111 
    }  
    # 虚拟IP
    virtual_ipaddress { 
        192.168.106.100/24
    } 
    track_script {
        check_nginx
    } 
}
END
else
cat > /etc/keepalived/keepalived.conf<<END
global_defs { 
   notification_email { 
     acassen@firewall.loc 
     failover@firewall.loc 
     sysadmin@firewall.loc 
   } 
   notification_email_from Alexandre.Cassen@firewall.loc  
   smtp_server 127.0.0.1 
   smtp_connect_timeout 30 
   router_id NGINX_BACKUP
} 

vrrp_script check_nginx {
    script "/etc/keepalived/check_nginx.sh"
}

vrrp_instance VI_1 { 
    state BACKUP 
    interface eth0
    virtual_router_id 51 # VRRP 路由 ID实例，每个实例是唯一的 
    priority 90
    advert_int 1
    authentication { 
        auth_type PASS      
        auth_pass 1111 
    }  
    virtual_ipaddress { 
        192.168.106.100/24
    } 
    track_script {
        check_nginx
    } 
}
END
fi &>>/dev/null
check "修改keepalived配置文件"

cat > /etc/keepalived/check_nginx.sh <<END
#!/bin/bash
counter=\`netstat -tunpl | grep nginx | wc -l\`
if [ \$counter -eq 0 ]; then
    service nginx start
    sleep 2
    counter=\`netstat -tunpl | grep nginx | wc -l\`
    if [ \$counter -eq 0 ]; then
        service  keepalived stop
    fi
fi
END
chmod +x /etc/keepalived/check_nginx.sh
check "配置check_nginx存活性检测"


systemctl  enable keepalived --now && systemctl status keepalived
check "启动keepalived服务"
