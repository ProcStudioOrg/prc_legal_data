# config/initializers/s3_config.rb
Rails.application.config.s3 = {
  profile_pictures_bucket: ENV.fetch('S3_PROFILE_PICTURES_BUCKET', 'oabapi-profile-pic')
}
