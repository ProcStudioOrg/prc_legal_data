# lib/tasks/generate_user.rake
# bundle exec rake db:seed_user
namespace :db do
  desc "Seed user data for the application"
  task seed_user: :environment do
    require 'faker'
    
    # Create an admin user and API key for testing
    begin
      # Check if user already exists
      if User.find_by(email: 'admin@example.com').nil?
        user = User.create!(
          email: 'admin@example.com',
          password_digest: BCrypt::Password.create('admin123'),
          admin: true
        )
        
        api_key = ApiKey.create!(
          user: user,
          active: true
        )
        
        puts "Admin user created successfully:"
        puts "Email: admin@example.com"
        puts "Password: admin123"
        puts "API Key: #{api_key.key}"
      else
        user = User.find_by(email: 'admin@example.com')
        # Create a new API key instead of finding existing one
        api_key = ApiKey.create!(
          user: user,
          active: true
        )
        
        puts "Admin user already exists. New API Key generated:"
        puts "API Key: #{api_key.key}"
      end
    rescue => e
      puts "Error creating admin user: #{e.message}"
      puts e.backtrace
    end
  end
end
