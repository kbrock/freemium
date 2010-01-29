require File.dirname(__FILE__) + '/../test_helper'

class ManualBillingTest < ActiveSupport::TestCase
  fixtures :users, :freemium_subscriptions, :freemium_subscription_plans, :freemium_credit_cards

  class FreemiumSubscription < ::FreemiumSubscription
    include Freemium::ManualBilling
  end

  def test_find_billable
    # making a one-off fixture set, basically
    create_billable_subscription # this subscription should be billable
    create_billable_subscription(:paid_through => Date.today) # this subscription should be billable
    create_billable_subscription(:coupon => FreemiumCoupon.create!(:description => "Complimentary", :discount_percentage => 100)) # should NOT be billable because it's free
    create_billable_subscription(:subscription_plan => freemium_subscription_plans(:free)) # should NOT be billable because it's free
    create_billable_subscription(:paid_through => Date.today + 1) # should NOT be billable because it's paid far enough out
    s = create_billable_subscription({},{:expire_on, Date.today + 1}) # should be billable because it's past due

    expirable = FreemiumSubscription.send(:find_billable)
    assert expirable.all? {|subscription| subscription.paid?}, "free subscriptions aren't billable"
    assert expirable.all? {|subscription| !subscription.in_trial?}, "subscriptions that have been paid are no longer in the trial period"
    assert expirable.all? {|subscription| subscription.paid_through <= Date.today}, "subscriptions paid through tomorrow aren't billable yet"
    assert_equal 3, expirable.size

    assert_equal expirable.size, FreemiumSubscription.run_billing.size
  end

  def test_overdue_payment_failure
    subscription = create_billable_subscription({},:billing_key => '2', :expire_on => Date.today + 2) # should NOT be billable because it's already expiring

    expirable = FreemiumSubscription.send(:find_billable)
    assert_equal 1, expirable.size, "Subscriptions in their grace period should be retried"

    assert_nothing_raised do
      transaction = subscription.charge!
      assert_equal Date.today + 2, subscription.expire_on, "Billing failed on existing overdue account but the expire_on date was changed"
    end
  end

  def test_overdue_payment_success
    subscription = create_billable_subscription({},:expire_on => Date.today + 2) # should NOT be billable because it's already expiring
    paid_through = subscription.paid_through

    expirable = FreemiumSubscription.send(:find_billable)
    assert_equal 1, expirable.size, "Subscriptions in their grace period should be retried"

    assert_nothing_raised do
      transaction = subscription.charge!
      assert_equal (paid_through >> 1).to_s, transaction.subscription.paid_through.to_s, "extended by a month"
      assert_nil subscription.expire_on, "Billing succeeded on existing overdue account but the expire_on date was not reset"
    end
  end

  def test_charging_a_subscription
    subscription = create_billable_subscription(
      :coupon => FreemiumCoupon.create!(:description => "Complimentary", :discount_percentage => 30)
    )
    paid_through = subscription.paid_through

    assert_nothing_raised do
      transaction = subscription.charge!
      assert_equal (paid_through >> 1).to_s, transaction.subscription.paid_through.to_s, "extended by a month"
    end

    subscription = subscription.reload
    assert !subscription.transactions.empty?
    assert subscription.transactions.last
    assert subscription.transactions.last.success?
    assert_equal 1747, subscription.transactions.last.amount_cents
    assert_not_nil subscription.transactions.last.message?
    assert (Time.now - 1.minute) < subscription.last_transaction_at
    assert !FreemiumTransaction.since(Date.today).empty?
    assert_equal subscription.rate, subscription.transactions.last.amount
    assert_equal (paid_through >> 1).to_s, subscription.reload.paid_through.to_s, "extended by a month"
  end


  def test_charging_a_subscription_aborted
    subscription = create_billable_subscription({
      :coupon => FreemiumCoupon.create!(:description => "Complimentary", :discount_percentage => 30)
    }, {
      :billing_key => "2" #it should fail (don't set first time through - want that to succeed)
    })

    paid_through = subscription.paid_through
    assert subscription.transactions.empty?
    #Freemium.gateway.expects(:charge)
    #subscription.expects(:receive_payment).raises(RuntimeError,"Failed")
    subscription.charge!
    assert !subscription.reload.transactions.empty?
  end

  def test_failing_to_charge_a_subscription
    subscription = create_billable_subscription({},:billing_key => '2') #make sure it fails
    paid_through = subscription.paid_through

    assert_nil subscription.expire_on
    assert_nothing_raised do
      subscription.charge!
    end
    assert_equal paid_through, subscription.reload.paid_through, "not extended"
    #subscriptions only expire if we ran it, it is out of grace, and we run again. don't make this check
    #assert_not_nil subscription.expire_on
    assert subscription.in_grace?
    assert !subscription.transactions.last.success?
  end

  def test_run_billing_calls_charge_on_billable
    subscription = create_billable_subscription
    FreemiumSubscription.stubs(:find_billable).returns([subscription])
    #subscription.expects(:charge!).once
    FreemiumSubscription.send :run_billing
  end

  protected

  def create_billable_subscription(options = {}, updates=nil)
    subscription=FreemiumSubscription.create!({
      :subscription_plan => freemium_subscription_plans(:premium),
      :subscribable => User.new(:name => 'a'),
      :paid_through => Date.today - 1,
      :credit_card => FreemiumCreditCard.sample
    }.merge(options))
    subscription.update_attributes(updates) if updates
    subscription
  end
end