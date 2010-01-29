module Freemium
  # adds manual billing functionality to the Subscription class
  module ManualBilling
    def self.included(base)
      base.extend ClassMethods
    end

    # Override if you need to charge something different than the rate (ex: yearly billing option)
    def installment_amount(options = {})
      self.rate(options)
    end

    # charges this subscription.
    # assumes, of course, that this module is mixed in to the Subscription model
    def charge!
      #convert active merchant transaction to our own and save immediately
      response = Freemium.gateway.purchase(self.installment_amount, billing_key)
      #billing_key ||=response.params['billingid']
      @transaction = self.transactions.create(self.active_merchant_trans_params(response, :billing_key => billing_key))

      self.last_transaction_at = Time.now # TODO this could probably now be inferred from the list of transactions
      self.save(false)
    
      #TODO: do we want this empty try/catch?
      begin
        if @transaction.success? 
          receive_payment!(@transaction)
        elsif !@transaction.subscription.in_grace?
          expire_after_grace!(@transaction)
        end
      rescue
      end
      
      @transaction
    end

    protected
    def active_merchant_trans_params(response, other_params={})
      #For the first charge, if there is no billing id, don't want to erase the new billing id with the previous (nil) value
      #other_params.delete(:billing_key) if other_params[:billing_key].blank?
      {
        :success      =>response.success?,
        :billing_key  =>response.params['billingid'],
        :amount_cents =>response.params['paid_amount'].to_f * 100, # subscription
        :message      =>response.message
      }.merge(other_params)
    end

    module ClassMethods
      # the process you should run periodically
      def run_billing
        # charge all billable subscriptions
        @transactions = find_billable.collect{|b| b.charge!}
        # actually expire any subscriptions whose time has come
        expire

        # send the activity report
        Freemium.mailer.deliver_admin_report(
          @transactions # Add in transactions
        ) if Freemium.admin_report_recipients && !@transactions.empty?
        
        @transactions
      end

      protected
      
      # a subscription is due on the last day it's paid through. so this finds all
      # subscriptions that expire the day *after* the given date. 
      # because of coupons we can't trust rate_cents alone and need to verify that the account is indeed paid?
      def find_billable
        self.paid.due.select{|s| s.paid?}
      end
    end
  end
end