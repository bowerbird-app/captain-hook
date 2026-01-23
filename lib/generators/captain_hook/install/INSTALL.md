===============================================================================

CaptainHook has been installed successfully!

The engine has been mounted at /captain_hook in your application.

Next steps:
1. Complete setup with: rails captain_hook:setup
   (This will handle migrations, encryption keys, and configuration)

Or do it manually:
1. Run 'rails captain_hook:install:migrations && rails db:migrate'
2. Setup encryption keys: 'rails db:encryption:init'
3. Add autoload paths to config/application.rb

To use the engine:
1. Start your Rails server
2. Visit http://localhost:3000/captain_hook

Health check:
- Run 'rails captain_hook:doctor' to validate your setup

===============================================================================
