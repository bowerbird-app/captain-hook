// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "controllers"
import { application } from "controllers/application"

// MakeupArtist Stimulus Controllers
import * as MakeupArtist from "makeup_artist"
MakeupArtist.register(application)
