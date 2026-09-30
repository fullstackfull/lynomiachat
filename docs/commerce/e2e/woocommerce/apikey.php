<?php
// Creates (or replaces) the read-only REST key "Lynomia Commerce E2E" and writes it to /tmp for the test harness only.
global $wpdb;
$wpdb->delete( $wpdb->prefix . 'woocommerce_api_keys', array( 'description' => 'Lynomia Commerce E2E' ) );
$ck = 'ck_' . wc_rand_hash(); $cs = 'cs_' . wc_rand_hash();
$wpdb->insert( $wpdb->prefix . 'woocommerce_api_keys', array(
	'user_id' => 1, 'description' => 'Lynomia Commerce E2E', 'permissions' => 'read',
	'consumer_key' => wc_api_hash( $ck ), 'consumer_secret' => $cs, 'truncated_key' => substr( $ck, -7 ),
) );
echo $ck . ' ' . $cs;
