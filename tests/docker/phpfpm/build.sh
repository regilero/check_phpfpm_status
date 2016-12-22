#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "******* Building"
docker build -t phpfpm_alone .
echo "****** remove old containers"
docker rm -f cont_phpfpm_alone||/bin/true
echo "******* Running"
HOSTIP=`ip -4 addr show scope global dev docker0 | grep inet | awk '{print \$2}' | cut -d / -f 1`
docker run --name cont_phpfpm_alone -p 9001:9000 -d phpfpm_alone
echo "******* docker ps"
docker ps
# if you want to edit files in a running docker (for tests, do not forget to get your copy back in conf dir)
#docker run -i -t --rm --volumes-from cont_phpfpm_alone --name cont_phpfpm_alonefiles debian /bin/bash
