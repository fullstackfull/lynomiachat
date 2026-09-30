#!/bin/bash
# wp-cli against WooCommerce test site N (1 = localhost:8081, 2 = :8082, 3 = :8083).
N=$1; shift
W=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$W/src/plugins/woocommerce
VOL=woo-html; DB=wordpress; [ "$N" != 1 ] && VOL=woo-html$N && DB=wordpress$N
docker run --rm -i --network woo-net --user 33:33 -v $VOL:/var/www/html -v $PLUGIN:/var/www/html/wp-content/plugins/woocommerce:ro \
  -e WORDPRESS_DB_HOST=woo-db -e WORDPRESS_DB_USER=wp -e WORDPRESS_DB_PASSWORD=wp -e WORDPRESS_DB_NAME=$DB mirror.gcr.io/library/wordpress:cli-php8.3 wp "$@"
