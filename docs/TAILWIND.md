# GemTemplate Tailwind CSS Setup

This document explains how Tailwind CSS is configured in the **GemTemplate** engine and the dummy app, including automatic rebuilds during development.

---

## Overview

The engine uses **Tailwind CSS 4** with the `tailwindcss-rails` gem. Tailwind watches for class usage in view templates and rebuilds the CSS automatically when changes are detected.

---

## Directory Structure

```
test/dummy/
├── app/assets/
│   ├── builds/
│   │   └── tailwind.css          # Compiled output (auto-generated)
│   ├── stylesheets/
│   │   └── application.css       # Standard Rails stylesheet
│   └── tailwind/
│       └── application.css       # Tailwind source file (entry point)
└── ...
```

| Path                                      | Purpose                                                      |
|-------------------------------------------|--------------------------------------------------------------|
| `app/assets/tailwind/application.css`     | Tailwind entry point; imports Tailwind and sets `@source`.   |
| `app/assets/builds/tailwind.css`          | Compiled CSS output consumed by the asset pipeline.          |

---

## Tailwind Entry Point

The file `app/assets/tailwind/application.css` configures Tailwind:

```css
@import "tailwindcss";

/* Include the engine's views in the Tailwind build */
@source "../../../../../app/views/**/*.erb";
```

### Key Directives

| Directive              | Description                                                                 |
|------------------------|-----------------------------------------------------------------------------|
| `@import "tailwindcss"`| Loads Tailwind's base, components, and utilities.                          |
| `@source "..."`        | Tells Tailwind where to scan for class names (engine views, host views).   |

> **Note:** The relative path `../../../../../app/views/**/*.erb` points from the dummy app up to the engine's `app/views` folder so Tailwind can detect classes used in engine templates.

---

## Auto-Rebuild in Development

### Procfile.dev

Located at `test/dummy/Procfile.dev`:

```
web: bin/rails server -b 0.0.0.0
css: bin/rails tailwindcss:watch
```

| Process | Command                         | Description                                      |
|---------|---------------------------------|--------------------------------------------------|
| `web`   | `bin/rails server -b 0.0.0.0`   | Starts the Rails server on all interfaces.       |
| `css`   | `bin/rails tailwindcss:watch`   | Watches for file changes and rebuilds CSS.       |

### bin/dev

The `bin/dev` script starts both processes using **Foreman**:

```bash
#!/usr/bin/env sh
if ! gem list foreman -i --silent; then
  echo "Installing foreman..."
  gem install foreman
fi

export PORT="${PORT:-3000}"
export RUBY_DEBUG_OPEN="true"
export RUBY_DEBUG_LAZY="true"

exec foreman start -f Procfile.dev "$@"
```

Run the development environment:

```bash
cd test/dummy
bin/dev
```

This starts both the Rails server and Tailwind watcher concurrently. Any change to `.erb`, `.html`, or source CSS files triggers an automatic CSS rebuild.

---

## Manual Build Commands

| Command                           | Description                                  |
|-----------------------------------|----------------------------------------------|
| `bin/rails tailwindcss:build`     | One-time build of Tailwind CSS.              |
| `bin/rails tailwindcss:watch`     | Watch mode; rebuilds on file changes.        |
| `bin/rails tailwindcss:clobber`   | Deletes compiled CSS in `app/assets/builds`. |

---

## Including Engine Views in Host Apps

When a host application installs the gem, the install generator adds this line to their Tailwind config:

```css
@source "../../vendor/bundle/**/gem_template/app/views/**/*.erb";
```

This ensures Tailwind scans the engine's views (installed via Bundler) for class names during the host app's CSS build.

If the generator cannot detect Tailwind, it prints instructions for manual setup.

---

## Asset Pipeline Integration

The compiled `tailwind.css` is served via the Rails asset pipeline:

```erb
<%= stylesheet_link_tag "tailwind", "data-turbo-track": "reload" %>
```

- **Turbo Drive** reloads the stylesheet automatically when it changes.
- No Sprockets or Propshaft preprocessing is needed; the file is already compiled.

---

## Adding Custom Styles

1. **Utility classes** – Use Tailwind utilities directly in your `.erb` templates.
2. **Custom CSS** – Add rules in `app/assets/tailwind/application.css` after the `@import`.
3. **Plugins** – Install Tailwind plugins via npm/yarn and reference them in your config.

Example custom styles:

```css
@import "tailwindcss";

@source "../../../../../app/views/**/*.erb";

/* Custom component */
.btn-primary {
  @apply bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700;
}
```

---

## Troubleshooting

| Issue                                 | Solution                                                                                   |
|---------------------------------------|--------------------------------------------------------------------------------------------|
| CSS not updating                      | Ensure `bin/rails tailwindcss:watch` is running (check Foreman output).                   |
| Classes not detected                  | Verify `@source` paths cover all template directories.                                     |
| `tailwind.css` missing               | Run `bin/rails tailwindcss:build` to generate the compiled file.                           |
| Foreman not installed                 | `bin/dev` will auto-install it, or run `gem install foreman` manually.                     |
| Port conflict                         | Set a different port: `PORT=3001 bin/dev`.                                                 |

---

## Files Reference

| File                                      | Purpose                                      |
|-------------------------------------------|----------------------------------------------|
| `test/dummy/app/assets/tailwind/application.css` | Tailwind entry point with `@source` paths.  |
| `test/dummy/app/assets/builds/tailwind.css`      | Compiled CSS output.                        |
| `test/dummy/Procfile.dev`                        | Foreman process definitions.                |
| `test/dummy/bin/dev`                             | Development startup script.                 |
| `lib/generators/gem_template/install/install_generator.rb` | Adds `@source` to host app Tailwind config. |

---

Happy styling! 🎨
