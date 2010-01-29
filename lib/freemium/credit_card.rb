require 'active_merchant/billing/expiry_date'
module Freemium
  module CreditCard

    def self.included(base)
      base.class_eval do
        include ActiveMerchant::Billing::CreditCardMethods
        include ActiveMerchant::Billing::CreditCardFormatting
        # Essential attributes for a valid, non-bogus creditcards
        attr_accessor :number, :month, :year, :first_name, :last_name

        # Required for Switch / Solo cards
        attr_accessor :start_month, :start_year, :issue_number

        # Optional verification_value (CVV, CVV2 etc). Gateways will try their best to 
        # run validation on the passed in value if it is supplied
        attr_accessor :verification_value

        attr_accessible :number, :month, :year, :first_name, :last_name, :start_month, :start_year, :issue_number, :verification_value, :card_type, :zip_code       
                
        has_one :subscription, :class_name => "FreemiumSubscription"
        
        before_validation :sanitize_data, :if => :changed?
        before_validation :set_table_data, :if => :changed?
      end
    end    
    
    ##
    ## Callbacks
    ##
    
    protected
    
    def sanitize_data #:nodoc: 
      self.month = month.to_i
      self.year  = year.to_i
      self.number = number.to_s.gsub(/[^\d]/, "")
      self.card_type.downcase! if card_type.respond_to?(:downcase)
      self.card_type = self.class.type?(number) if card_type.blank?
    end
    
    def set_table_data
      self.display_number  = self.class.mask(number) unless number.blank?
      self.expiration_date = expiry_date.expiration
    end

    public

    def type
      card_type
    end
    
    ##
    ## From ActiveMerchant::Billing::CreditCard
    ##    

    # Provides proxy access to an expiry date object
    def expiry_date
      ActiveMerchant::Billing::CreditCard::ExpiryDate.new(month, year)
    end

    def name?
      first_name? && last_name?
    end
    
    def first_name?
      !@first_name.blank?
    end

    def display_number
      @display_number||self.class.mask(number)
    end
    
    def last_name?
      !@last_name.blank?
    end

    def expired?
      expiry_date.expired?
    end

    def name
      "#{first_name} #{last_name}"
    end

    def address
      unless @address
        @address = Address.new
        @address.zip = self.zip_code
      end
      @address
    end
    
    ##
    ## Overrides
    ##
    
    # We're overriding AR#changed? to include instance vars that aren't persisted to see if a new card is being set
    def changed?
      card_type_changed? || [:number, :month, :year, :first_name, :last_name, :start_month, :start_year, :issue_number, :verification_value].any? {|attr| !self.send(attr).nil?}
    end

    ##
    ## Validation
    ##
    
    def validate
      # We don't need to run validations unless it's a new record or the
      # record has changed
      return unless new_record? || changed?
      
      validate_essential_attributes

      # Bogus card is pretty much for testing purposes. Lets just skip these extra tests if its used
      return if card_type == 'bogus'

      validate_card_type
      validate_card_number
      validate_switch_or_solo_attributes
    end
    
    private
    
    def validate_card_number #:nodoc:
      errors.add :number, "is not a valid credit card number" unless self.class.valid_number?(number)
      unless errors.on(:number) || errors.on(:type)
        errors.add :card_type, "is not the correct card type" unless self.class.matching_type?(number, card_type)
      end
    end
    
    def validate_card_type #:nodoc:
      errors.add :card_type, "is required" if card_type.blank?
      errors.add :card_type, "is invalid"  unless self.class.card_companies.keys.include?(card_type)
    end
    
    def validate_essential_attributes #:nodoc:
      errors.add :first_name, "cannot be empty"      if @first_name.blank?
      errors.add :last_name,  "cannot be empty"      if @last_name.blank?
      errors.add :month,      "is not a valid month" unless valid_month?(@month)
      errors.add :year,       "expired"              if expired?
      errors.add :year,       "is not a valid year"  unless valid_expiry_year?(@year)
    end
    
    def validate_switch_or_solo_attributes #:nodoc:
      if %w[switch solo].include?(card_type)
        unless valid_month?(@start_month) && valid_start_year?(@start_year) || valid_issue_number?(@issue_number)
          errors.add :start_month,  "is invalid"      unless valid_month?(@start_month)
          errors.add :start_year,   "is invalid"      unless valid_start_year?(@start_year)
          errors.add :issue_number, "cannot be empty" unless valid_issue_number?(@issue_number)
        end
      end
    end
  end
end