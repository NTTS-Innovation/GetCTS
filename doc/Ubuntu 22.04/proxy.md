# Configure proxy on Ubuntu Server 22.04

This script assumes standard installation with no changes in regards to proxy

Copy the text below to a text editor and update "export proxy_server=[server]:[ip]" and replace [server] with the actual IP or hostname of the proxy server and [port] with proxy server port. Once the text has been updated copy everything and paste it in a shell on the server

```
sudo -i
export proxy_server=[server]:[port]
sudo mkdir -p /etc/systemd/system/docker.service.d
cat << EOF > /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=http://$proxy_server" "HTTPS_PROXY=http://$proxy_server"
EOF
systemctl daemon-reload
systemctl restart docker
export HTTP_PROXY=http://$proxy_server
export HTTPS_PROXY=http://$proxy_server
export http_proxy=http://$proxy_server
export https_proxy=http://$proxy_server
echo "http_proxy=$http_proxy" >> /etc/environment
echo "https_proxy=$https_proxy" >> /etc/environment
echo "HTTP_PROXY=$HTTP_PROXY" >> /etc/environment
echo "HTTPS_PROXY=$HTTPS_PROXY" >> /etc/environment
echo "export http_proxy=$http_proxy" >> /etc/profile.d/http_proxy.sh
echo "export https_proxy=$https_proxy" >> /etc/profile.d/http_proxy.sh
echo "export HTTP_PROXY=$HTTP_PROXY" >> /etc/profile.d/http_proxy.sh
echo "export HTTPS_PROXY=$HTTPS_PROXY" >> /etc/profile.d/http_proxy.sh
chmod +x  /etc/profile.d/http_proxy.sh
echo "Acquire::http::proxy \"$http_proxy/\";" > /etc/apt/apt.conf.d/80proxy
echo "Acquire::https::proxy \"$https_proxy/\";" >> /etc/apt/apt.conf.d/80proxy
```
