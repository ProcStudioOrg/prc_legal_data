# config/initializers/s3_config.rb
Rails.application.config.s3 = {
  profile_pictures_bucket: ENV.fetch('S3_PROFILE_PICTURES_BUCKET', 'cropped-lawyer-pictures-ld'),
  cna_pictures_bucket: ENV.fetch('S3_CNA_PICTURES_BUCKET', 'scraped-lawyers-ld')
}
