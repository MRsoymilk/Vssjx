FROM php:8.3-apache-bookworm@sha256:b79a53c3fb1dd4b9f350a8d99d84951512b6c21044e61bbecfee8af030b3722e

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpng-dev libjpeg62-turbo-dev libfreetype6-dev libzip-dev unzip \
    && docker-php-ext-configure gd --with-jpeg --with-freetype \
    && docker-php-ext-install -j2 gd zip \
    && a2enmod rewrite headers expires deflate setenvif remoteip \
    && rm -rf /var/lib/apt/lists/*

# Build context is prepared separately; never use the game repository or .env.
COPY flarum.tar.gz /tmp/flarum.tar.gz
RUN echo '9f941e27bd8cafc7f81440574832a13eeef47486947a46cf4e5b307126a0d61a  /tmp/flarum.tar.gz' | sha256sum -c - \
    && mkdir -p /var/www/flarum \
    && tar -xzf /tmp/flarum.tar.gz -C /var/www/flarum \
    && sed -i '/RewriteEngine on/a\  RewriteBase /flarum/' /var/www/flarum/public/.htaccess \
    && rm /tmp/flarum.tar.gz
COPY composer.phar /tmp/composer.phar
ARG COMPOSER_SHA384
RUN test -n "$COMPOSER_SHA384" \
    && echo "$COMPOSER_SHA384  /tmp/composer.phar" | sha384sum -c -
WORKDIR /var/www/flarum
RUN COMPOSER_ALLOW_SUPERUSER=1 php /tmp/composer.phar require flarum-lang/chinese-simplified:2.0.0 \
      --update-no-dev --prefer-dist --no-interaction --no-progress --no-plugins --no-scripts \
    && php /tmp/composer.phar check-platform-reqs --no-dev \
    && rm /tmp/composer.phar \
    && mkdir /opt/flarum-seed \
    && cp -a public/assets /opt/flarum-seed/assets \
    && cp -a storage /opt/flarum-seed/storage \
    && rm -r public/assets storage \
    && ln -s /data/assets public/assets \
    && ln -s /data/storage storage \
    && ln -s /data/config.php config.php

COPY site.php /var/www/flarum/site.php
COPY apache.conf /etc/apache2/sites-available/000-default.conf
COPY limits.conf /etc/apache2/conf-enabled/flarum-limits.conf
COPY php.ini /usr/local/etc/php/conf.d/flarum.ini
COPY initialize.sh /usr/local/bin/flarum-initialize
RUN chmod 755 /usr/local/bin/flarum-initialize

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=8s --start-period=60s --retries=3 \
  CMD php -r '$c=stream_context_create(["http"=>["timeout"=>5,"header"=>"Host: 47.93.114.190\r\nX-Forwarded-Proto: https\r\n"]]); $h=@get_headers("http://127.0.0.1/flarum/",false,$c); exit($h && str_contains($h[0],"200") ? 0 : 1);'
CMD ["apache2-foreground"]
