# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# MakeupArtist controllers
pin "makeup_artist", to: "makeup_artist/index.js"
pin_all_from Gem::Specification.find_by_name("makeup_artist").gem_dir + "/app/javascript/makeup_artist/controllers", under: "makeup_artist/controllers"
