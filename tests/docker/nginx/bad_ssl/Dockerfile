FROM nginx:stable
COPY conf/vhosts.conf /etc/nginx/conf.d/vhosts.conf
COPY conf/fastcgi_params.conf /etc/nginx/fastcgi_params.conf
RUN rm /etc/nginx/conf.d/default.conf
COPY certs/nginx-selfsigned-bad.key /etc/nginx/ssl/server.key
COPY certs/nginx-selfsigned-bad.crt /etc/nginx/ssl/server.crt
