FROM php:8.3-fpm

RUN apt-get update && apt-get install -y \
    git curl zip unzip libzip-dev libpq-dev \
    libonig-dev libxml2-dev supervisor \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-install \
    pdo pdo_pgsql pgsql \
    bcmath mbstring opcache zip

RUN pecl install redis \
    && docker-php-ext-enable redis

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

COPY docker-fpm/php/php.ini /usr/local/etc/php/conf.d/custom.ini
COPY docker-fpm/php/php-fpm.conf /usr/local/etc/php-fpm.d/www.conf
COPY docker-fpm/php/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN mkdir -p /var/log/supervisor /var/log/php-fpm

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
