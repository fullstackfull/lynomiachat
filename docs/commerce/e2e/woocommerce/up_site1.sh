#!/bin/bash
# Real WooCommerce test store for Lynomia Commerce E2E (WooCommerce built from the official 10.9.4 source tag).
set -e
W=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$W/src/plugins/woocommerce
docker network inspect woo-net >/dev/null 2>&1 || docker network create woo-net >/dev/null
docker rm -f woo-db woo-wp >/dev/null 2>&1 || true
docker volume rm -f woo-html >/dev/null 2>&1 || true
docker pull -q mirror.gcr.io/library/mariadb:11 >/dev/null; docker pull -q mirror.gcr.io/library/wordpress:php8.3-apache >/dev/null; docker pull -q mirror.gcr.io/library/wordpress:cli-php8.3 >/dev/null
docker run -d --name woo-db --network woo-net -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=wordpress -e MARIADB_USER=wp -e MARIADB_PASSWORD=wp mirror.gcr.io/library/mariadb:11 >/dev/null
# REST requests are treated as TLS by the test store only, so WooCommerce accepts HTTP Basic auth on this local http site
# (WooCommerce only allows Basic auth over TLS; Lynomia reaches it through the explicit trusted-host policy).
docker run -d --name woo-wp --network woo-net -p 8081:80 -v woo-html:/var/www/html \
  -v $PLUGIN:/var/www/html/wp-content/plugins/woocommerce:ro \
  -e WORDPRESS_DB_HOST=woo-db -e WORDPRESS_DB_USER=wp -e WORDPRESS_DB_PASSWORD=wp -e WORDPRESS_DB_NAME=wordpress \
  -e WORDPRESS_CONFIG_EXTRA="if (strpos(\$_SERVER['REQUEST_URI'] ?? '', '/wp-json/') !== false) { \$_SERVER['HTTPS'] = 'on'; }" \
  mirror.gcr.io/library/wordpress:php8.3-apache >/dev/null
for i in $(seq 1 60); do curl -s -o /dev/null http://localhost:8081/ && break; sleep 2; done
wp() { docker run --rm -i --network woo-net --user 33:33 -v woo-html:/var/www/html -v $PLUGIN:/var/www/html/wp-content/plugins/woocommerce:ro \
  -e WORDPRESS_DB_HOST=woo-db -e WORDPRESS_DB_USER=wp -e WORDPRESS_DB_PASSWORD=wp -e WORDPRESS_DB_NAME=wordpress mirror.gcr.io/library/wordpress:cli-php8.3 wp "$@"; }
for i in $(seq 1 30); do wp db check >/dev/null 2>&1 && break; sleep 2; done
wp core install --url=http://localhost:8081 --title="Syria Cosmetics" --admin_user=admin --admin_password=Admin-Pass-123 --admin_email=admin@example.com --skip-email
wp rewrite structure '/%postname%/' --hard
wp plugin activate woocommerce
wp option update woocommerce_default_country 'SA:SA-01'
wp option update woocommerce_currency SAR
wp option update woocommerce_coming_soon no
wp wc hpos enable
wp eval-file - < $W/seed.php                 # the scenarios in docs/commerce/09-woocommerce-e2e.md §2
wp eval-file - < $W/apikey.php 2>/dev/null > $W/key.txt   # read-only REST key (consumer key + secret)
wp eval 'echo "WooCommerce " . WC()->version . " HPOS=" . (Automattic\WooCommerce\Utilities\OrderUtil::custom_orders_table_usage_is_enabled() ? "on" : "off") . PHP_EOL;'
curl -s http://localhost:8081/wp-json/ | head -c 300; echo
