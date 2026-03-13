# lib/tasks/rotate_api_keys.rake
# bundle exec rake api_keys:rotate                           # rotate all users
# bundle exec rake api_keys:rotate[user@example.com]         # rotate specific user
# bundle exec rake api_keys:create_read[user@example.com]    # create read-only key
# bundle exec rake api_keys:create_admin[user@example.com]   # create admin key
namespace :api_keys do
  desc "Rotate API keys for all users or a specific user (preserves roles)"
  task :rotate, [:email] => :environment do |t, args|
    puts "=== API Key Rotation ==="
    puts "Starting at #{Time.current}"

    begin
      if args[:email].present?
        user = User.find_by(email: args[:email])
        if user.nil?
          puts "Error: User '#{args[:email]}' not found"
          exit 1
        end
        rotate_keys_for_user(user)
      else
        User.find_each { |user| rotate_keys_for_user(user) }
      end

      puts "\nRotation completed at #{Time.current}"
    rescue => e
      puts "Error: #{e.message}"
      exit 1
    end
  end

  desc "Create a read-only API key for a user"
  task :create_read, [:email] => :environment do |t, args|
    create_key_for_user(args[:email], "read")
  end

  desc "Create an admin API key for a user"
  task :create_admin, [:email] => :environment do |t, args|
    create_key_for_user(args[:email], "admin")
  end

  desc "List all active API keys"
  task list: :environment do
    puts "\n=== Active API Keys ==="
    puts "%-30s %-8s %-50s %-20s" % ["User Email", "Role", "API Key", "Created At"]
    puts "-" * 110

    ApiKey.includes(:user).where(active: true).order(:role, created_at: :desc).each do |api_key|
      puts "%-30s %-8s %-50s %-20s" % [
        api_key.user.email,
        api_key.role,
        api_key.key,
        api_key.created_at.strftime("%Y-%m-%d %H:%M:%S")
      ]
    end
  end

  private

  def rotate_keys_for_user(user)
    ActiveRecord::Base.transaction do
      # Get existing roles before deactivating
      active_roles = user.api_keys.where(active: true).pluck(:role).uniq

      old_keys_count = user.api_keys.where(active: true).update_all(active: false)

      puts "\nUser: #{user.email}"
      puts "  Deactivated #{old_keys_count} old key(s)"

      # Create new keys preserving each role
      active_roles.each do |role|
        new_key = ApiKey.create!(user: user, active: true, role: role)
        puts "  New #{role} key: #{new_key.key}"
      end
    end
  rescue => e
    puts "Error rotating keys for #{user.email}: #{e.message}"
    raise
  end

  def create_key_for_user(email, role)
    unless email.present?
      puts "Usage: bundle exec rake api_keys:create_#{role}[user@example.com]"
      exit 1
    end

    user = User.find_by(email: email)
    if user.nil?
      puts "Error: User '#{email}' not found"
      exit 1
    end

    key = ApiKey.create!(user: user, active: true, role: role)
    puts "#{role.capitalize} API key created for #{email}:"
    puts "  #{key.key}"
  rescue => e
    puts "Error: #{e.message}"
    exit 1
  end
end
