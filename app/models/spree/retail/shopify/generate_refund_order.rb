module Spree
  module Retail
    module Shopify
      class GenerateRefundOrder
        def initialize(shopify_refund)
          @shopify_refund = shopify_refund
          @order = find_order(shopify_refund)
        end

        def process
          if order.returned?
            logger.info("SKIP - [Spree: #{@order.number} / Shopify: #{@order.pos_order_number}] - refund already imported")
            return true
          end

          create_return_authorization(order, return_items)
          customer_return = create_customer_return(return_items)
          create_reimbursement(customer_return)

          return true

        rescue => e
          logger.error("FAILURE - [Spree: #{@order.try(:number)} / Shopify: #{order_id_for(shopify_refund)}]: #{e}")
          return false
        end

        private

        attr_reader :shopify_refund, :order

        def return_items
          @return_items ||= begin
            return_items = []
            shopify_refund.refund_line_items.each do |rli|
              inventory_unit = find_inventory_by_shopify_variant_id(order, rli.line_item.variant_id)
              return_items << create_return_item(inventory_unit)
            end

            return_items
          end
        end

        def find_inventory_by_shopify_variant_id(order, shopify_variant_id)
          order.shipments.first.inventory_units.find { |unit| unit.variant.pos_variant_id.to_i == shopify_variant_id.to_i }
        end

        def create_return_item(inventory_unit)
          Spree::ReturnItem.create(
            inventory_unit: inventory_unit,
            preferred_reimbursement_type: reimbursement_type
          ).tap(&:accept!)
        end

        def create_return_authorization(order, return_items)
          Spree::ReturnAuthorization.create(
            order: order,
            stock_location: stock_location_to_refund,
            return_reason_id: return_reason.id,
            memo: "Automated refund made by Shopify",
            return_items: return_items
          )
        end

        def create_customer_return(return_items)
          Spree::CustomerReturn.create(
            stock_location: stock_location_to_refund,
            return_items: return_items
          )
        end

        def create_reimbursement(customer_return)
          reimbursement = Spree::Reimbursement.build_from_customer_return(customer_return)
          reimbursement.save
          reimbursement.pos_refunded!
          reimbursement.perform!
        end

        def find_order(shopify_refund)
          Spree::Order.find_by(pos_order_id: order_id_for(shopify_refund))
        end

        def order_id_for(shopify_refund)
          shopify_refund.prefix_options[:order_id]
        end

        def return_reason
          Spree::ReturnReason.first
        end

        def stock_location_to_refund
          Spree::StockLocation.first
        end

        def reimbursement_type
          Spree::ReimbursementType.first
        end

        def logger
          Logger.new(Rails.root.join('log/import_refund.log'))
        end
      end
    end
  end
end
