#!/bin/bash
# Builds the WooCommerce 10.9.4 plugin from the official source tag (wordpress.org downloads are not reachable from the
# test environment). Output: ./src/plugins/woocommerce, mounted read-only into the WordPress containers.
set -e
W=$(cd "$(dirname "$0")" && pwd)
rm -rf $W/src
git clone -q --depth 1 --filter=blob:none --sparse --branch 10.9.4 https://github.com/woocommerce/woocommerce $W/src
(cd $W/src && git sparse-checkout set plugins/woocommerce packages/php)
cd $W/src/plugins/woocommerce
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --prefer-source --no-scripts --no-interaction
php bin/generate-feature-config.php   # includes/react-admin/feature-config.php, normally created by `pnpm build`
