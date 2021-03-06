class Claim < ActiveRecord::Base
	validates_presence_of :member_id, :points
  belongs_to :user, foreign_key: 'member_id'

  scope :submitted, where(transaction_status: 'submitted')
  scope :unsubmitted, where('transaction_status IS NULL')
  scope :paid, where(transaction_status: 'tesSUCCESS')
  scope :needs_rate, where('rate IS NULL')
  scope :has_rate, where('rate IS NOT NULL')

  def self.failed_with_error(error)
    self.where(transaction_status: error)
  end

  def self.failed_with_insuffiecient_xrp_but_over_current_reserve
    self.where(transaction_status: 'tecNO_DST_INSUF_XRP').where('xrp_disbursed >= ?', ENV['RESERVE_AMOUNT'].to_i)
  end

  def self.failed_with_insuffiecient_xrp_and_under_current_reserve
    self.where(transaction_status: 'tecNO_DST_INSUF_XRP').where('xrp_disbursed < ?', ENV['RESERVE_AMOUNT'].to_i)
  end

  def user_ripple_address
    User.where(member_id: self.member_id).first.ripple_address
  end

  def confirm_payment(confirmation)
    self.transaction_hash = confirmation['transaction_hash']
    self.transaction_status = confirmation['transaction_status']
    self.save
  end

  def duplicate_and_retry
    duplicate = self.dup
    duplicate.transaction_status = nil
    duplicate.transaction_hash = nil
    duplicate.save
    if duplicate.persisted?
      self.destroy
      duplicate.enqueue
    end
  end

  def rollover!
    if !self.rolled_over?
      new_claim = Claim.where('transaction_status IS NULL').where(member_id: self.member_id).first
      if new_claim
        new_claim.xrp_disbursed = new_claim.xrp_disbursed + self.xrp_disbursed
        new_claim.save

        self.rolled_over = true
        self.save

        puts "rolled over #{self.xrp_disbursed} xrp to claim #{new_claim.id}"
      end
    end
  end

  def enqueue
    PaymentRequestQueue.push({
      unique_id: self.id,
      ripple_address: user_ripple_address,
      xrp_amount: self.xrp_disbursed
    })

    self.transaction_status = 'submitted'
    self.save
  end
end
