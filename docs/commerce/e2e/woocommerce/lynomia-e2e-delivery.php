<?php
/*
 * Lynomia Commerce realtime E2E only (docs/commerce/27-phase7-8-e2e.md), installed as a must-use plugin of the test
 * store. WooCommerce runs in a container and Lynomia on the host, so a delivery addressed to Lynomia's
 * http://localhost:3100 goes to the container network's gateway instead; WordPress's safe HTTP would otherwise refuse
 * that private address and port. The webhooks themselves (topics, secret, signature) are WooCommerce's own.
 */
const LYNOMIA_E2E_GATEWAY = '__GATEWAY__';
add_filter( 'woocommerce_webhook_delivery_url', function ( $url ) {
	return str_replace( 'http://localhost:3100/', 'http://' . LYNOMIA_E2E_GATEWAY . ':3100/', $url );
} );
add_filter( 'http_request_args', function ( $args, $url ) {
	if ( 0 === strpos( $url, 'http://' . LYNOMIA_E2E_GATEWAY . ':3100/' ) ) {
		$args['reject_unsafe_urls'] = false;
	}
	return $args;
}, 10, 2 );
