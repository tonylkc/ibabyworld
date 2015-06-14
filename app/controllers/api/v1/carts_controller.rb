class Api::V1::CartsController < ApplicationController

	PAYDOLLAR_URL = "https://test.paydollar.com/b2cDemo/eng/payment/payForm.jsp"
	PAYDOLLAR_MERCHANTID = "1"
	PAYDOLLAR_CURRENCY_CODE_HKD = "344"
	PAYDOLLAR_PAYMENT_TYPE = "CC"
	PAYDOLLAR_SECRET = "gMAVIEGVpqHvxoNEqbrZRuBDFT1B0icW"
	PD_SEP = "|"

	# PAYDOLLAR_MERCHANTID = "88588405"

	RETURNURL = "http://localhost:3000/#/bb-shop/thankyou"
	CANCELURL = "http://localhost:3000/#/bb-shop/cancel"

	STATUS_NEW = 1
	STATUS_SIGNED_IN = 2
	STATUS_PAYPAL_ISSUED = 3
	STATUS_PAYPAL_EXECUTED = 4
	STATUS_PAYDOLLAR_ISSUED = 5
	STATUS_PAYDOLLAR_EXECUTED = 6

	require 'paypal-sdk-rest'
	include PayPal::SDK::OpenIDConnect

	def getcart(params)
		if (params.has_key?(:memberid))
			@cart = ShoppingCart.find_or_create_by(member_id: params[:memberid])
		elsif (params.has_key?(:cookie))
			@cart = ShoppingCart.find_or_create_by(cookies: params[:cookie])
		else 
			@cart = ShoppingCart.find_or_create_by(cookies: 'ibabyworld')
		end
		return @cart
	end

	def getinvoiceno(cart)
		return 'I' << Time.now.strftime("%Y%m%d") << cart.id.to_s.rjust(8, '0')
	end

	def mycart
		@cart = getcart(params)
		render json: @cart.to_json(include: [:shopping_cart_items])	
	end

	def additemtocart
		if (params.has_key?(:cartid) and params.has_key?(:productid))
			@product = Product.find(params[:productid])
			cartitem = ShoppingCartItem.create do |i|
				i.shopping_cart_id = params[:cartid]
				i.product_id = params[:productid]
				i.qty = 1
				i.unit_price = @product.unit_price
			end
			cartitem.save
			response_success({ :cartitem => cartitem })
		end
	end

	def changecartitemqty
		if (params.has_key?(:cartitemid))
			# cartitem = ShoppingCartItem.find(params[:cartitemid]) do |i|
			# 	i.qty = params[:qty]
			# end
			cartitem = ShoppingCartItem.find(params[:cartitemid])
			cartitem.update_attributes(qty: params[:qty])
			render :json => { 
			      :status => 'ok',
			      :cartitem => cartitem 
			    }.to_json
		end
	end

	def removecartitem
		if (params.has_key?(:cartitemid))
			ShoppingCartItem.find(params[:cartitemid]).destroy
			render :json => { 
			      :status => 'ok'
			    }.to_json
		end
	end

	def checkoutpaypal

		conf = PayPal::SDK.configure({
		  :mode => "sandbox",
		})

		@cart = getcart(params)
		@cartitems = ShoppingCartItem.where(shopping_cart_id: @cart.id )

		@payment = PayPal::SDK::REST::Payment.new({
		  :intent => "sale",
		  :payer => {
		    :payment_method => "paypal" },
		  :redirect_urls => {
		    :return_url => RETURNURL,
		    :cancel_url => CANCELURL },
		  :transactions => [ {
		    :amount => {
		      :currency => "HKD" },
		    :description => "iBabyWorld Purchase" } ] } )

		total=0
		itemno=0
		@cartitems.each do |i|
			@product = Product.find(i.product_id)
			name = @product.short_description_en_US
	       	@payment.transactions[0].item_list.items[itemno] = {
	                quantity: i.qty,
	                name: name,
	                price: '%.2f' % i.unit_price,
	                currency: 'HKD'
	            }
			total += i.unit_price.to_f * i.qty
			itemno += 1
		end

		@payment.transactions[0].amount.total = '%.2f' % total

		paymentresult = @payment.create
		@cart.update_attributes!({:paymentid => @payment.id, :paymenturl => @payment.links[1].href, :status => STATUS_PAYPAL_ISSUED})
		@cart.save

		render :json => { 
				:paymentid => @payment.id,
				:link => @payment.links[1].href,
				:success => paymentresult,
		    	:status => 'ok'
		    }.to_json
	end

	def executepaypal
		if (params.has_key?(:paymentid) and params.has_key?(:payerid))

			conf = PayPal::SDK.configure({
			  :mode => "sandbox",
			})
			@payment = PayPal::SDK::REST::Payment.find(params[:paymentid])
			@result = @payment.execute( :payer_id => params[:payerid] )

			render :json => { 
					:payment => @payment,
					:result => @result,
			    	:status => 'ok'
			    }.to_json
		end
	end

	def checkoutpaydollar
		@cart = getcart(params)
		@cartitems = ShoppingCartItem.where(shopping_cart_id: @cart.id)
		total=0
		itemno=0
		@cartitems.each do |i|
			total += i.unit_price.to_f * i.qty
			itemno += 1
		end
		amount = '%.2f' % total
		hashstring = PAYDOLLAR_MERCHANTID + PD_SEP + getinvoiceno(@cart) + PD_SEP + PAYDOLLAR_CURRENCY_CODE_HKD
		hashstring << PD_SEP + amount + PD_SEP + PAYDOLLAR_PAYMENT_TYPE + PD_SEP + PAYDOLLAR_SECRET

		@w = Digest::SHA1.hexdigest("#{hashstring}")

		render :json => { 
				:postUrl => PAYDOLLAR_URL,
				:orderRef => getinvoiceno(@cart),
				:payMethod => "CC",
				:merchantId => PAYDOLLAR_MERCHANTID, #88588405
				:amount => amount,
				:items => itemno,
				:payType => "N",
				:lang => "E",
				:currCode => PAYDOLLAR_CURRENCY_CODE_HKD,
				:mpsMode => "NIL",
				:successUrl => RETURNURL,
				:failUrl => CANCELURL,
				:cancelUrl => CANCELURL,
				:secureHash => @w,
		    	:status => 'ok'
		    }.to_json

	end

end