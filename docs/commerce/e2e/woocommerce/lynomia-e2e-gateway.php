<?php
/*
 * Lynomia Commerce order actions E2E only (docs/commerce/33-phase9-10-e2e.md), installed as a must-use plugin of the
 * disposable test store, never on a merchant's store. A payment gateway that supports refunds the way a real one does
 * (WC_Payment_Gateway::process_refund) without moving money, so refunds go through WooCommerce's real refund flow:
 *
 *   13.13  the gateway declines the refund (WooCommerce deletes the refund it created and answers an error)
 *   7.77   the gateway answers after 35 seconds, longer than Lynomia waits (an answer lost to a timeout); the refund is
 *          then made, so Lynomia must find it by reading the store, never by sending it again
 *   other  refunded at once
 *
 * Every call is kept in the option lynomia_e2e_gateway_calls, and every email WordPress would send in the option
 * lynomia_e2e_mails instead of being sent, so the test can count what reached the gateway and the customer.
 */
add_action( 'plugins_loaded', function () {
	if ( ! class_exists( 'WC_Payment_Gateway' ) ) {
		return;
	}

	class Lynomia_E2E_Gateway extends WC_Payment_Gateway {
		public function __construct() {
			$this->id                 = 'lynomia_e2e';
			$this->method_title       = 'Lynomia E2E Card';
			$this->method_description = 'Test-only gateway of the Lynomia Commerce E2E. Moves no money.';
			$this->title              = 'Lynomia E2E Card';
			$this->enabled            = 'yes';
			$this->supports           = array( 'products', 'refunds' );
		}

		public function process_payment( $order_id ) {
			wc_get_order( $order_id )->payment_complete( 'e2e_' . $order_id );
			return array( 'result' => 'success', 'redirect' => '' );
		}

		public function process_refund( $order_id, $amount = null, $reason = '' ) {
			$amount = wc_format_decimal( $amount, 2 );
			$calls  = get_option( 'lynomia_e2e_gateway_calls', array() );
			$calls[] = array( 'order_id' => (int) $order_id, 'amount' => $amount, 'at' => time() );
			update_option( 'lynomia_e2e_gateway_calls', $calls, false );

			if ( '13.13' === $amount ) {
				return new WP_Error( 'lynomia_e2e_declined', 'The card issuer declined this refund.' );
			}
			if ( '7.77' === $amount ) {
				sleep( 35 );
			}
			wc_get_order( $order_id )->add_order_note( sprintf( 'Lynomia E2E Card refunded %s.', $amount ) );
			return true;
		}
	}

	add_filter( 'woocommerce_payment_gateways', function ( $gateways ) {
		$gateways[] = 'Lynomia_E2E_Gateway';
		return $gateways;
	} );
} );

add_filter( 'pre_wp_mail', function ( $short_circuit, $atts ) {
	$mails   = get_option( 'lynomia_e2e_mails', array() );
	$mails[] = array( 'to' => $atts['to'], 'subject' => $atts['subject'], 'at' => time() );
	update_option( 'lynomia_e2e_mails', $mails, false );
	return true;
}, 10, 2 );
