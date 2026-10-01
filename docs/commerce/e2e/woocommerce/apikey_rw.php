<?php
// Creates (or replaces) the read/write REST key "Lynomia Commerce Realtime E2E": WooCommerce creates webhooks only for a
// key with write permission (docs/commerce/24-realtime-architecture.md §4). Written to stdout for the test harness only.
global $wpdb;
$wpdb->delete( $wpdb->prefix . 'woocommerce_api_keys', array( 'description' => 'Lynomia Commerce Realtime E2E' ) );
$ck = 'ck_' . wc_rand_hash(); $cs = 'cs_' . wc_rand_hash();
$wpdb->insert( $wpdb->prefix . 'woocommerce_api_keys', array(
	'user_id' => 1, 'description' => 'Lynomia Commerce Realtime E2E', 'permissions' => 'read_write',
	'consumer_key' => wc_api_hash( $ck ), 'consumer_secret' => $cs, 'truncated_key' => substr( $ck, -7 ),
) );
echo $ck . ' ' . $cs;
