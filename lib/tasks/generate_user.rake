# lib/tasks/generate_user.rake
# bundle exec rake db:seed_user
namespace :db do
  desc "Seed user with admin and read-only API keys"
  task seed_user: :environment do
    begin
      user = User.find_by(email: 'admin@example.com')

      if user.nil?
        user = User.create!(
          email: 'admin@example.com',
          password_digest: BCrypt::Password.create('admin123'),
          admin: true
        )
        puts "Admin user created: admin@example.com"
      else
        puts "Admin user already exists: admin@example.com"
      end

      # Create admin API key
      admin_key = ApiKey.create!(user: user, active: true, role: "admin")
      puts "\nAdmin API Key (full CRUD access):"
      puts "  #{admin_key.key}"

      # Create read-only API key
      read_key = ApiKey.create!(user: user, active: true, role: "read")
      puts "\nRead-only API Key (GET requests only):"
      puts "  #{read_key.key}"
    rescue => e
      puts "Error: #{e.message}"
      puts e.backtrace
    end
  end
end
