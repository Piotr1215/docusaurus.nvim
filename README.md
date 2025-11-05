# Docusaurus.nvim

Neovim plugin for Docusaurus documentation workflows with version-aware content insertion and intelligent imports.

> **Note:** Opinionated plugin designed for specific Docusaurus project structures with versioned documentation folders.

## Features

- **Version-Aware Insertion**: Automatically filters partials/URLs by current version context
- **Smart Imports**: Auto-detects `@site` vs relative imports based on project structure
- **Content Management**: Insert components, partials, code blocks, and URL references
- **Plugin Tools**: Scaffold new plugins and browse Docusaurus API

## Requirements

- Neovim 0.8.0+
- telescope.nvim
- Git
- curl (for API browsing)

## Installation

```lua
-- lazy.nvim
{
  "Piotr1215/docusaurus.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("docusaurus").setup()
  end,
}
```

## Quick Start

```lua
require("docusaurus").setup()

-- Content insertion
vim.keymap.set("n", "<leader>ic", "<cmd>DocusaurusInsertComponent<cr>")
vim.keymap.set("n", "<leader>ip", "<cmd>DocusaurusInsertPartial<cr>")
vim.keymap.set("n", "<leader>ib", "<cmd>DocusaurusInsertCodeBlock<cr>")
vim.keymap.set("n", "<leader>iu", "<cmd>DocusaurusInsertURL<cr>")

-- Plugin tools
vim.keymap.set("n", "<leader>dpc", "<cmd>DocusaurusCreatePlugin<cr>")
vim.keymap.set("n", "<leader>dpa", "<cmd>DocusaurusBrowseAPI<cr>")
```

## Commands

| Command | Description |
|---------|-------------|
| `:DocusaurusInsertComponent` | Insert component from `src/components` |
| `:DocusaurusInsertPartial` | Insert partial from `_partials`, `_fragments`, `_code` directories |
| `:DocusaurusInsertCodeBlock` | Insert code block with raw-loader import |
| `:DocusaurusInsertURL` | Insert markdown link to documentation file |
| `:DocusaurusCreatePlugin` | Scaffold new Docusaurus plugin |
| `:DocusaurusBrowseAPI` | Browse Docusaurus configuration API |

## Version-Aware Filtering

When editing files, the plugin detects your current version context and filters results accordingly:

**Editing `vcluster_versioned_docs/version-0.20.x/guide.mdx`:**
- Partials: Shows `version-0.20.x/_partials` + root `docs/_*` folders
- URLs: Shows only `version-0.20.x` docs
- Excludes other versions and projects

**Editing `vcluster/install/guide.mdx` (main folder):**
- Partials: Shows `vcluster/_partials` + root `docs/_*` folders
- URLs: Shows only `vcluster/` docs
- Excludes `platform/` and versioned folders

**Editing `docs/shared-guide.mdx` (non-versioned):**
- Shows all files (no filtering)

## Configuration

```lua
require("docusaurus").setup({
  -- Components directory (default: {git-root}/src/components)
  components_dir = "~/project/src/components",

  -- Directories to search for partials
  -- Default: { "_partials", "_fragments", "_code" }
  partials_dirs = { "_partials", "_fragments", "_code" },

  -- Path patterns that use @site imports (non-versioned content)
  -- Default: { "^docs/_" } matches any docs/_* directory
  allowed_site_paths = { "^docs/_" },
})
```

## How It Works

### Components
1. Shows Telescope picker with components from `src/components`
2. Inserts `<ComponentName />` at cursor
3. Adds `import ComponentName from '@site/src/components/ComponentName';` after frontmatter

### Partials
1. Searches for `_partials`, `_fragments`, `_code` directories (filtered by version context)
2. Shows results with root `docs/_*` partials at the top
3. Prompts for import name
4. Inserts `<PartialName />` at cursor
5. Adds appropriate import (skips if import name already exists):
   - `@site` for root `docs/_*` content
   - Relative imports for versioned content

### Code Blocks
1. Searches partial directories for code files (filtered by version context)
2. Inserts `<CodeBlock language="..." title="...">{PartialName}</CodeBlock>`
3. Adds `import CodeBlock from '@theme/CodeBlock'`
4. Adds appropriate import (relative or `@site`)

### URL References
1. Searches for `.md` and `.mdx` files (filtered by version context, excludes `_*` directories)
2. Prompts for link text
3. Inserts `[Link Text](../../../relative/path)` at cursor (relative path from current file)

## API

```lua
local docusaurus = require("docusaurus")

-- Content insertion
docusaurus.select_component()
docusaurus.select_partial()
docusaurus.select_code_block()
docusaurus.insert_url_reference()

-- Plugin tools
docusaurus.create_plugin()
docusaurus.browse_api()

-- Utility
docusaurus.generate_plugin_template(opts)
docusaurus.scaffold_plugin(opts)
docusaurus.get_docusaurus_version()
docusaurus.get_config_options(version)
docusaurus.get_config()

-- Testing helpers
docusaurus.get_version_context(file_path, git_root)
docusaurus.path_matches_context(path, context, git_root)
```

## License

MIT
