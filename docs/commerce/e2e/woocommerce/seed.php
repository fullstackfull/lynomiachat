<?php
// Seeds the WooCommerce test store with the Lynomia Commerce E2E scenarios. Idempotent: wipes previous seed data first.
foreach ( wc_get_orders( array( 'limit' => -1, 'return' => 'ids' ) ) as $id ) { wc_get_order( $id )->delete( true ); }
foreach ( get_users( array( 'role' => 'customer', 'fields' => 'ID' ) ) as $uid ) { wp_delete_user( $uid ); }
foreach ( wc_get_products( array( 'limit' => -1, 'return' => 'ids' ) ) as $pid ) { wp_delete_post( $pid, true ); }

function lyn_product( $name, $price, $sku, $virtual = false ) {
	$p = new WC_Product_Simple();
	$p->set_name( $name ); $p->set_regular_price( $price ); $p->set_sku( $sku ); $p->set_virtual( $virtual );
	$p->set_status( 'publish' ); $p->save();
	return $p;
}
$serum  = lyn_product( 'سيروم الورد للوجه', '120.00', 'SERUM-01' );
$oil    = lyn_product( 'Argan Hair Oil', '85.50', 'ARGAN-02' );
$lotion = lyn_product( 'لوشن العود', '64.25', 'OUD-03' );
$card   = lyn_product( 'Gift Card 100', '100.00', 'GIFT-100', true );

function lyn_customer( $email, $first, $last, $phone, $billing_email = null ) {
	$c = new WC_Customer();
	$c->set_email( $email ); $c->set_username( strtok( $email, '@' ) ); $c->set_password( wp_generate_password() );
	$c->set_first_name( $first ); $c->set_last_name( $last );
	$c->set_billing_first_name( $first ); $c->set_billing_last_name( $last ); $c->set_billing_phone( $phone );
	$c->set_billing_email( $billing_email ?? $email ); $c->set_billing_country( 'SA' ); $c->set_billing_city( 'Riyadh' );
	$c->save();
	return $c;
}
$layla = lyn_customer( 'layla.haddad@example.com', 'ليلى', 'حداد', '+966501234567' );
$sara  = lyn_customer( 'sara.ali@example.com', 'Sara', 'Ali', '+966550000111' );
$noor  = lyn_customer( 'noor.ali@example.com', 'Noor', 'Ali', '0550000111' );
$hana  = lyn_customer( 'hana@example.com', 'Hana', 'Saeed', '+966560000001', 'family@example.com' );
$rami  = lyn_customer( 'rami@example.com', 'Rami', 'Saeed', '+966560000002', 'family@example.com' );
$mona  = lyn_customer( 'mona.saleh@example.com', 'منى', 'صالح', '+966509998877' );

// $spec: customer (WC_Customer|null for guest), billing overrides, items [[product, qty]], shipping [title, cost]|null,
// payment [method, title], flow (callable on the saved order), days ago.
function lyn_order( $customer, $billing, $items, $shipping, $payment, $flow, $days_ago ) {
	$order = wc_create_order( array( 'customer_id' => $customer ? $customer->get_id() : 0 ) );
	foreach ( $items as $item ) { $order->add_product( $item[0], $item[1] ); }
	$address = array_merge( array(
		'first_name' => $customer ? $customer->get_billing_first_name() : '',
		'last_name'  => $customer ? $customer->get_billing_last_name() : '',
		'email'      => $customer ? $customer->get_billing_email() : '',
		'phone'      => $customer ? $customer->get_billing_phone() : '',
		'address_1'  => 'King Fahd Road 12', 'city' => 'Riyadh', 'postcode' => '12211', 'country' => 'SA',
	), $billing );
	$order->set_address( $address, 'billing' );
	if ( $shipping ) {
		$order->set_address( array_diff_key( $address, array( 'email' => 1 ) ), 'shipping' );
		$line = new WC_Order_Item_Shipping();
		$line->set_method_title( $shipping[0] ); $line->set_method_id( 'flat_rate' ); $line->set_total( $shipping[1] );
		$order->add_item( $line );
	}
	$order->set_payment_method( $payment[0] ); $order->set_payment_method_title( $payment[1] );
	$order->set_currency( 'SAR' );
	$order->calculate_totals();
	$order->set_date_created( time() - $days_ago * DAY_IN_SECONDS );
	$order->save();
	$flow( $order );
	return $order;
}
$card_pay = array( 'stripe', 'Credit card' );
$bacs     = array( 'bacs', 'Direct bank transfer' );
$cod      = array( 'cod', 'Cash on delivery' );
$paid     = function ( $o ) { $o->payment_complete( 'txn_' . $o->get_id() ); };
$complete = function ( $o ) use ( $paid ) { $paid( $o ); $o->update_status( 'completed' ); };

$ids = array();
// Layla: 7 orders (five-plus), registered, E.164 phone.
$ids['layla_completed_multi'] = lyn_order( $layla, array(), array( array( $serum, 1 ), array( $oil, 2 ) ), array( 'Aramex Express', '25' ), $card_pay, $complete, 30 );
$ids['layla_processing_paid'] = lyn_order( $layla, array(), array( array( $lotion, 1 ) ), array( 'Flat rate', '15' ), $card_pay, $paid, 20 );
$ids['layla_cancelled']       = lyn_order( $layla, array(), array( array( $oil, 1 ) ), array( 'Flat rate', '15' ), $card_pay, function ( $o ) { $o->update_status( 'cancelled' ); }, 15 );
$ids['layla_on_hold_bacs']    = lyn_order( $layla, array(), array( array( $serum, 2 ) ), array( 'Flat rate', '15' ), $bacs, function ( $o ) { $o->update_status( 'on-hold' ); }, 10 );
$ids['layla_refunded']        = lyn_order( $layla, array(), array( array( $lotion, 2 ) ), array( 'Flat rate', '15' ), $card_pay, function ( $o ) use ( $paid ) {
	$paid( $o ); wc_create_refund( array( 'order_id' => $o->get_id(), 'amount' => $o->get_total(), 'reason' => 'Damaged' ) ); }, 7 );
$ids['layla_partial_refund']  = lyn_order( $layla, array(), array( array( $serum, 1 ), array( $lotion, 1 ) ), array( 'Aramex Express', '25' ), $card_pay, function ( $o ) use ( $complete ) {
	$complete( $o ); wc_create_refund( array( 'order_id' => $o->get_id(), 'amount' => '64.25', 'reason' => 'One item' ) ); }, 4 );
$ids['layla_cod_processing']  = lyn_order( $layla, array(), array( array( $oil, 1 ), array( $lotion, 1 ), array( $serum, 1 ) ), array( 'Flat rate', '15' ), $cod,
	function ( $o ) { $o->update_status( 'processing' ); }, 1 );
// Plugin-specific tracking meta (Shipment Tracking extension format) on one order: Lynomia must ignore it by default.
$o = wc_get_order( $ids['layla_completed_multi']->get_id() );
$o->update_meta_data( '_wc_shipment_tracking_items', array( array( 'tracking_provider' => 'aramex', 'tracking_number' => 'ARX123456', 'custom_tracking_link' => 'https://evil.example/track' ) ) );
$o->save();

// Omar: guest, local-format phone, one pending (unpaid) and one virtual-only (no shipping) completed order.
$omar = array( 'first_name' => 'Omar', 'last_name' => 'Khalil', 'email' => 'Omar.Khalil@Example.com', 'phone' => '0551112233' );
$ids['omar_pending']          = lyn_order( null, $omar, array( array( $serum, 1 ) ), array( 'Flat rate', '15' ), $card_pay, function ( $o ) {}, 3 );
$ids['omar_virtual_no_ship']  = lyn_order( null, $omar, array( array( $card, 1 ) ), null, $card_pay, $complete, 2 );
$ids['omar_failed']           = lyn_order( null, $omar, array( array( $oil, 1 ) ), array( 'Flat rate', '15' ), $card_pay, function ( $o ) { $o->update_status( 'failed' ); }, 2 );

// Duplicate phone: Sara (+966550000111) and Noor (0550000111) are the same E.164 number.
$ids['sara_processing']       = lyn_order( $sara, array(), array( array( $oil, 1 ) ), array( 'Flat rate', '15' ), $card_pay, $paid, 5 );
$ids['noor_completed']        = lyn_order( $noor, array(), array( array( $lotion, 1 ) ), array( 'Flat rate', '15' ), $card_pay, $complete, 6 );
// Duplicate billing email: Hana and Rami both bill to family@example.com.
$ids['hana_processing']       = lyn_order( $hana, array(), array( array( $serum, 1 ) ), array( 'Flat rate', '15' ), $card_pay, $paid, 8 );
$ids['rami_completed']        = lyn_order( $rami, array(), array( array( $oil, 1 ) ), array( 'Flat rate', '15' ), $card_pay, $complete, 9 );
// Mona: registered, no orders.

$out = array( 'customers' => array(), 'orders' => array() );
foreach ( compact( 'layla', 'sara', 'noor', 'hana', 'rami', 'mona' ) as $key => $c ) { $out['customers'][ $key ] = $c->get_id(); }
foreach ( $ids as $key => $order ) { $o = wc_get_order( $order->get_id() ); $out['orders'][ $key ] = array( $o->get_id(), $o->get_status(), $o->get_total() ); }
echo wp_json_encode( $out, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE ) . PHP_EOL;
