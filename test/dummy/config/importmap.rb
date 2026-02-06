# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# CaptainHook engine controllers
begin
  captain_hook_path = Bundler.rubygems.find_name("captain_hook").first&.full_gem_path || Rails.root.join("../..")
  pin_all_from "#{captain_hook_path}/app/javascript/controllers", under: "controllers"
rescue StandardError => e
  Rails.logger.warn "Could not load captain_hook importmap: #{e.message}"
end
