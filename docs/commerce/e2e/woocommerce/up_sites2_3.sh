#!/bin/bash
# Two more WooCommerce test sites: 2 = "Damascus Perfumes" (:8082), 3 = "Aleppo Soap" (:8083). Same DB server as site 1.
set -e
W=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$W/src/plugins/woocommerce
for N in 2 3; do
  TITLE=$([ $N = 2 ] && echo "Damascus Perfumes" || echo "Aleppo Soap")
  docker exec woo-db mariadb -uroot -proot -e "CREATE DATABASE IF NOT EXISTS wordpress$N; GRANT ALL ON wordpress$N.* TO 'wp'@'%';"
  docker rm -f woo-wp$N >/dev/null 2>&1 || true
  docker volume rm -f woo-html$N >/dev/null 2>&1 || true
  docker run -d --name woo-wp$N --network woo-net -p 808$N:80 -v woo-html$N:/var/www/html \
    -v $PLUGIN:/var/www/html/wp-content/plugins/woocommerce:ro \
    -e WORDPRESS_DB_HOST=woo-db -e WORDPRESS_DB_USER=wp -e WORDPRESS_DB_PASSWORD=wp -e WORDPRESS_DB_NAME=wordpress$N \
    -e WORDPRESS_CONFIG_EXTRA="if (strpos(\$_SERVER['REQUEST_URI'] ?? '', '/wp-json/') !== false) { \$_SERVER['HTTPS'] = 'on'; }" \
    mirror.gcr.io/library/wordpress:php8.3-apache >/dev/null
  for i in $(seq 1 60); do curl -s -o /dev/null http://localhost:808$N/ && break; sleep 2; done
  $W/wpn.sh $N core install --url=http://localhost:808$N --title="$TITLE" --admin_user=admin --admin_password=Admin-Pass-123 --admin_email=admin@example.com --skip-email
  $W/wpn.sh $N rewrite structure '/%postname%/' --hard
  $W/wpn.sh $N plugin activate woocommerce
  $W/wpn.sh $N option update woocommerce_default_country 'SA:SA-01'
  $W/wpn.sh $N option update woocommerce_currency SAR
  $W/wpn.sh $N option update woocommerce_coming_soon no
  $W/wpn.sh $N wc hpos enable >/dev/null 2>&1 || true
  $W/wpn.sh $N eval-file - $N < $W/seed_extra.php
  $W/wpn.sh $N eval-file - < $W/apikey.php 2>/dev/null > $W/key$N.txt
done
