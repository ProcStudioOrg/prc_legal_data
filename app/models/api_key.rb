# app/models/api_key.rb
class ApiKey < ApplicationRecord
  belongs_to :user

  validates :role, inclusion: { in: %w[admin read] }

  before_create :generate_key

  def admin?
    role == "admin"
  end

  def read_only?
    role == "read"
  end

  private

  def generate_key
    self.key = SecureRandom.hex(24)
  end
end
