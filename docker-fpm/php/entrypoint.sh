#!/bin/sh
set -e

chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache
chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# Passport OAuth keys must be 600/660, not world-readable
for key in /var/www/html/storage/oauth-private.key /var/www/html/storage/oauth-public.key; do
    if [ -f "$key" ]; then
        chmod 660 "$key"
    fi
done

exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
