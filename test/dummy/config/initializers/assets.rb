# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Add MakeupArtist gem JavaScript path for Propshaft (Rails 8+) if available
begin
  Rails.application.config.assets.paths << Gem::Specification.find_by_name("makeup_artist").gem_dir + "/app/javascript"
rescue Gem::MissingSpecError
  # makeup_artist gem not available, skip
end
