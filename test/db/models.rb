class User < ActiveRecord::Base
  has_many :subscriptions, :as => :subscribable
end

class FreemiumCouponRedemption < ActiveRecord::Base
  include Freemium::CouponRedemption
end

class FreemiumSubscription < ActiveRecord::Base
  include Freemium::Subscription
end

class FreemiumSubscriptionPlan < ActiveRecord::Base
  include Freemium::SubscriptionPlan
end

class FreemiumCreditCard < ActiveRecord::Base
  include Freemium::CreditCard
end

class FreemiumCoupon < ActiveRecord::Base
  include Freemium::Coupon
end

class FreemiumTransaction < ActiveRecord::Base
  belongs_to :subscription, :class_name => 'FreemiumSubscription'
  include Freemium::Transaction
end

class FreemiumSubscriptionChange < ActiveRecord::Base
  include Freemium::SubscriptionChange
end