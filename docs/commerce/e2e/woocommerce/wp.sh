#!/bin/bash
# wp-cli against the WooCommerce test store.
W=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$W/src/plugins/woocommerce
docker run --rm -i --network woo-net --user 33:33 -v woo-html:/var/www/html -v $PLUGIN:/var/www/html/wp-content/plugins/woocommerce:ro \
  -e WORDPRESS_DB_HOST=woo-db -e WORDPRESS_DB_USER=wp -e WORDPRESS_DB_PASSWORD=wp -e WORDPRESS_DB_NAME=wordpress mirror.gcr.io/library/wordpress:cli-php8.3 wp "$@"
