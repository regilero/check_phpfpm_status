#!/bin/bash
set -e
cd "$(dirname "$0")"
ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
echo "******* Building"
cd classic
docker build -t nginx_classic .
cd ../low_ssl
docker build -t nginx_low_ssl .
cd ../bad_ssl
docker build -t nginx_bad_ssl .
cd ..
echo "****** remove old containers"
docker rm -f cont_nginx_classic||/bin/true
docker rm -f cont_nginx_low_ssl||/bin/true
docker rm -f cont_nginx_bad_ssl||/bin/true
echo "******* Running"
HOSTIP=`ip -4 addr show scope global dev docker0 | grep inet | awk '{print \$2}' | cut -d / -f 1`
docker run --name cont_nginx_classic --add-host=dockerhost:${HOSTIP} -p 8801:80  -p 8443:443 -d nginx_classic
docker run --name cont_nginx_low_ssl --add-host=dockerhost:${HOSTIP} -p 8802:80  -p 9443:443 -d nginx_low_ssl
docker run --name cont_nginx_bad_ssl --add-host=dockerhost:${HOSTIP} -p 8803:80  -p 10443:443 -d nginx_bad_ssl
echo "******* docker ps"
docker ps
# /etc/ssl/certs:/etc/ssl/certs -v /etc/ssl/private:/etc/ssl/private