#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "* Creating phpfpm container."
./docker/phpfpm/build.sh
echo "* Creating several Nginx containers using this previous one and some SSL stuff."
./docker/nginx/build.sh

