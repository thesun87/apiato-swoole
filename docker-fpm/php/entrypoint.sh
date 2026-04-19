#!/bin/sh
set -e

chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache
chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
