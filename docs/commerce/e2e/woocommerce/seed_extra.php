<?php
// Sites 2 and 3: the same shopper (Layla, same email and phone as on site 1) with this store's own orders.
$site = $args[0];
foreach ( wc_get_orders( array( 'limit' => -1, 'return' => 'ids' ) ) as $id ) { wc_get_order( $id )->delete( true ); }
foreach ( get_users( array( 'role' => 'customer', 'fields' => 'ID' ) ) as $uid ) { wp_delete_user( $uid ); }
$product = new WC_Product_Simple();
$product->set_name( '2' === $site ? 'عطر الياسمين الدمشقي' : 'صابون الغار الحلبي' );
$product->set_regular_price( '2' === $site ? '210.00' : '45.00' ); $product->set_status( 'publish' ); $product->save();
$c = new WC_Customer();
$c->set_email( 'layla.haddad@example.com' ); $c->set_username( 'layla' ); $c->set_password( wp_generate_password() );
$c->set_first_name( 'ليلى' ); $c->set_last_name( 'حداد' ); $c->set_billing_phone( '0501234567' ); $c->set_billing_country( 'SA' );
$c->set_billing_email( 'layla.haddad@example.com' ); $c->set_billing_first_name( 'ليلى' ); $c->set_billing_last_name( 'حداد' );
$c->save();
$qty = '2' === $site ? array( 1, 3 ) : array( 6 );
foreach ( $qty as $i => $q ) {
	$order = wc_create_order( array( 'customer_id' => $c->get_id() ) );
	$order->add_product( $product, $q );
	$address = array( 'first_name' => 'ليلى', 'last_name' => 'حداد', 'email' => 'layla.haddad@example.com', 'phone' => '0501234567',
		'address_1' => 'Baghdad Street 3', 'city' => 'Damascus', 'country' => 'SA' );
	$order->set_address( $address, 'billing' );
	$order->set_address( $address, 'shipping' );
	$line = new WC_Order_Item_Shipping(); $line->set_method_title( 'SMSA Express' ); $line->set_method_id( 'flat_rate' ); $line->set_total( '30' );
	$order->add_item( $line );
	$order->set_payment_method( 'stripe' ); $order->set_payment_method_title( 'Credit card' ); $order->set_currency( 'SAR' );
	$order->calculate_totals(); $order->set_date_created( time() - ( 3 - $i ) * DAY_IN_SECONDS ); $order->save();
	$order->payment_complete( 'txn_' . $order->get_id() );
	if ( 0 === $i ) { $order->update_status( 'completed' ); }
}
echo wp_json_encode( array( 'site' => $site, 'customer' => $c->get_id(), 'orders' => wc_get_orders( array( 'limit' => -1, 'return' => 'ids' ) ) ) ) . PHP_EOL;
