# lib/tasks/rotate_api_keys.rake
# bundle exec rake api_keys:rotate
# bundle exec rake api_keys:rotate[user@example.com]
namespace :api_keys do
  desc "Rotate API keys for all users or a specific user"
  task :rotate, [:email] => :environment do |t, args|
    puts "=== API Key Rotation ==="
    puts "Starting API key rotation at #{Time.current}"
    
    begin
      if args[:email].present?
        # Rotate API key for specific user
        user = User.find_by(email: args[:email])
        if user.nil?
          puts "Error: User with email '#{args[:email]}' not found"
          exit 1
        end
        
        rotate_keys_for_user(user)
      else
        # Rotate API keys for all users
        User.find_each do |user|
          rotate_keys_for_user(user)
        end
      end
      
      puts "\nAPI key rotation completed successfully at #{Time.current}"
    rescue => e
      puts "Error during API key rotation: #{e.message}"
      puts e.backtrace
      exit 1
    end
  end
  
  desc "List all active API keys"
  task list: :environment do
    puts "\n=== Active API Keys ==="
    puts "%-30s %-50s %-20s" % ["User Email", "API Key", "Created At"]
    puts "-" * 100
    
    ApiKey.includes(:user).where(active: true).order(created_at: :desc).each do |api_key|
      puts "%-30s %-50s %-20s" % [
        api_key.user.email,
        api_key.key,
        api_key.created_at.strftime("%Y-%m-%d %H:%M:%S")
      ]
    end
  end
  
  private
  
  def rotate_keys_for_user(user)
    ActiveRecord::Base.transaction do
      # Deactivate all existing API keys for this user
      old_keys_count = user.api_keys.where(active: true).update_all(active: false)
      
      # Generate a new API key
      new_api_key = ApiKey.create!(
        user: user,
        active: true
      )
      
      puts "\nUser: #{user.email}"
      puts "  - Deactivated #{old_keys_count} old API key(s)"
      puts "  - New API Key: #{new_api_key.key}"
      puts "  - Created at: #{new_api_key.created_at}"
    end
  rescue => e
    puts "Error rotating keys for user #{user.email}: #{e.message}"
    raise
  end
end