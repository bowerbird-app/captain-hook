# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# MakeupArtist controllers
# Temporarily disabled - uncomment when gem is properly configured
# begin
#   makeup_artist_path = Bundler.rubygems.find_name("makeup_artist").first&.full_gem_path
#   if makeup_artist_path
#     pin "makeup_artist", to: "makeup_artist/index.js"
#     pin_all_from "#{makeup_artist_path}/app/javascript/makeup_artist/controllers", under: "makeup_artist/controllers"
#   end
# rescue StandardError => e
#   Rails.logger.warn "Could not load makeup_artist importmap: #{e.message}"
# end
