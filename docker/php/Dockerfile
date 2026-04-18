FROM php:8.3-cli

# System dependencies
RUN apt-get update && apt-get install -y \
    git curl zip unzip libzip-dev libpq-dev libssl-dev \
    libonig-dev libxml2-dev libbrotli-dev \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions
RUN docker-php-ext-install \
    pdo pdo_pgsql pgsql \
    bcmath mbstring opcache zip pcntl

# Redis extension
RUN pecl install redis \
    && docker-php-ext-enable redis

# Swoole extension
RUN pecl install swoole \
    && docker-php-ext-enable swoole

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Supervisor
RUN apt-get update && apt-get install -y supervisor \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

COPY docker/php/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
