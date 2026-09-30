<?php
global $wpdb;
$uid = username_exists( 'lyn_subscriber' ) ?: wp_create_user( 'lyn_subscriber', wp_generate_password(), 'lyn_subscriber@example.com' );
$wpdb->delete( $wpdb->prefix . 'woocommerce_api_keys', array( 'description' => 'Lynomia subscriber key' ) );
$ck = 'ck_' . wc_rand_hash(); $cs = 'cs_' . wc_rand_hash();
$wpdb->insert( $wpdb->prefix . 'woocommerce_api_keys', array( 'user_id' => $uid, 'description' => 'Lynomia subscriber key', 'permissions' => 'read',
	'consumer_key' => wc_api_hash( $ck ), 'consumer_secret' => $cs, 'truncated_key' => substr( $ck, -7 ) ) );
echo $ck . ' ' . $cs;
