FROM php:7.1.0-fpm
COPY app /usr/src/app
WORKDIR /usr/src/app
RUN rm /usr/local/etc/php-fpm.d/www.conf
COPY conf/www.conf /usr/local/etc/php-fpm.d/www.conf
# VOLUME /usr/local/etc/php-fpm.d
