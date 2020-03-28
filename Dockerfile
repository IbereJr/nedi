FROM alpine:3.11
LABEL Maintainer="Ibere Luiz Di Tizio Jr <ibere.tizio@gmail.com>" \
      Description="Lightweight container with Nginx 1.16, PHP-FPM 7.3 & Nedi 1.8 based on Alpine Linux."

### Set some default values
ENV DB_HOST=mariadb \
    DB_NAME=nedi \
    DB_USER=nedi \
    DB_PASS=nedi \
    NFDUMP_DATA_BASE_DIR=/data/nfdump/datafiles \
    NEDI_CERT_INFO="/C=CH/ST=ZH/L=Zurich/O=NeDi Consulting/OU=R&D" \
    NEDI_SOURCE_URL=http://www.nedi.ch/pub \
    NEDI_VERSION=1.8C \
    PHP_INI_FILE=/etc/php7/conf.d/custom.ini

# Install packages
RUN apk --no-cache add php7 php7-fpm php7-mysqli php7-json php7-openssl php7-curl \
    php7-zlib php7-xml php7-phar php7-intl php7-dom php7-xmlreader php7-ctype php7-session \
    php7-mbstring php7-gd php7-snmp nginx supervisor curl openssl perl-algorithm-diff \
    perl-dbd-mysql perl-dbi perl-net-snmp perl-net-telnet perl-rrd perl-socket6 tzdata

# Adjust crontab
RUN cp /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime &&\
    echo "America/Sao_Paulo" > /etc/timezone &&\
    mkdir -p /etc/crontabs && apk del tzdata 
COPY config/nedi_crontab /etc/crontabs/root

# Configure nginx
COPY config/nginx.conf /etc/nginx/nginx.conf

# Remove default server definition
RUN rm /etc/nginx/conf.d/default.conf

# Configure PHP-FPM
COPY config/fpm-pool.conf /etc/php7/php-fpm.d/www.conf
COPY config/php.ini /etc/php7/conf.d/custom.ini

# Install NEDI
RUN adduser -H -s /sbin/nologin -D nedi && \ 
    mkdir -p /data/nedi && \
    cd /data/nedi && \
    wget ${NEDI_SOURCE_URL}/nedi-${NEDI_VERSION}.pkg && \
    tar -xf /data/nedi/nedi*.pkg && \
    mkdir -p /data/nedi/ssl/private && \
    chown -R nedi:nedi /data/nedi && \
    mkdir -p /data/log/nedi && \
    chown -R nedi.nedi /data/log/nedi && \
    ln -s /data/nedi/nedi.conf /etc/nedi.conf && \
    sed -i '/nedipath/s/\/var\/nedi/\/data\/nedi/g' /data/nedi/nedi.conf && \
    sed -i '/dbhost/s/localhost/'"${DB_HOST}"'/g' /data/nedi/nedi.conf && \
    sed -i '/dbuser/s/nedi/'"${DB_USER}"'/g' /data/nedi/nedi.conf && \
    sed -i '/dbname/s/nedi/'"${DB_NAME}"'/g' /data/nedi/nedi.conf && \
    sed -i '/dbpass/s/		.*/		'"${DB_PASS}"'/g' nedi.conf && \
    sed -i -e "s/^upload_max_filesize.*/upload_max_filesize = 2G/"  "${PHP_INI_FILE}" && \
    sed -i -e "s/^post_max_size.*/post_max_size = 1G/"  "${PHP_INI_FILE}"  
#    rm nedi*.pkg && \
#    mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.orig

# Configure supervisord
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Setup document root
RUN mkdir -p /var/www/html

# Make sure files/folders needed by the processes are accessable when they run under the nobody user
RUN chown -R nobody.nobody /var/www/html && \
  chown -R nobody.nobody /run && \
  chown -R nobody.nobody /var/lib/nginx && \
  chown -R nobody.nobody /var/log/nginx

# Switch to use a non-root user from here on
USER nobody

### Networking Configuration
EXPOSE 8080 162/UDP 8443 1514/UDP

WORKDIR /data/nedi/

# Let supervisord start nginx & php-fpm
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

# Configure a healthcheck to validate that everything is up&running
HEALTHCHECK --timeout=10s CMD curl --silent --fail http://127.0.0.1:8080/fpm-ping
