// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/vault_lite_web.ex",
    "../lib/vault_lite_web/**/*.*ex"
  ],
  theme: {
    extend: {
      colors: {
        brand: "#FD4F00",
      }
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    require("daisyui"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Heroicon classes
    plugin(function({matchComponents, theme}) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"]
      ]
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
          let name = path.basename(file, ".svg") + suffix
          values[name] = {name, fullPath: path.join(iconsDir, dir, file)}
        })
      })
      matchComponents({
        "hero": ({name, fullPath}) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--hero-${name})`,
            "mask": `var(--hero-${name})`,
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            "display": "inline-block",
            "width": theme("spacing.5"),
            "height": theme("spacing.5")
          }
        }
      }, {values})
    })
  ],
  daisyui: {
    themes: [
      {
        light: {
          "primary": "#6366f1",        // indigo-500
          "primary-focus": "#4f46e5",  // indigo-600
          "primary-content": "#ffffff",
          "secondary": "#f59e0b",      // amber-500
          "accent": "#10b981",         // emerald-500
          "neutral": "#374151",        // gray-700
          "base-100": "#ffffff",       // white
          "base-200": "#f9fafb",       // gray-50
          "base-300": "#e5e7eb",       // gray-200
          "base-content": "#1f2937",   // gray-800
          "info": "#3b82f6",           // blue-500
          "success": "#10b981",        // emerald-500
          "warning": "#f59e0b",        // amber-500
          "error": "#ef4444",          // red-500
        },
      },
      {
        dark: {
          "primary": "#818cf8",        // indigo-400
          "primary-focus": "#6366f1",  // indigo-500
          "primary-content": "#1e1b4b", // indigo-900
          "secondary": "#fbbf24",      // amber-400
          "accent": "#34d399",         // emerald-400
          "neutral": "#f3f4f6",        // gray-100
          "base-100": "#1f2937",       // gray-800
          "base-200": "#111827",       // gray-900
          "base-300": "#374151",       // gray-700
          "base-content": "#f9fafb",   // gray-50
          "info": "#60a5fa",           // blue-400
          "success": "#34d399",        // emerald-400
          "warning": "#fbbf24",        // amber-400
          "error": "#f87171",          // red-400
        },
      },
    ],
    darkTheme: "dark",
    base: true,
    styled: true,
    utils: true,
  },
}
