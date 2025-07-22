# Docusaurus.nvim

Streamline your Docusaurus documentation workflow in Neovim.

> [!IMPORTANT]
> This plugin is designed for a specific Docusaurus project structure and makes several assumptions:
> - Uses `@site` directive ONLY for non-versioned content in `docs/_partials/`, `docs/_fragments/`, etc.
> - Versioned content (e.g., `vcluster_versioned_docs/`) uses relative imports
> - Expects partial content to be organized in underscore directories: `_partials`, `_fragments`, or `_code`
> - Components are assumed to be in `src/components` with a specific structure
> - Raw loader imports (`!!raw-loader!`) preserve file content as-is for code blocks
> - This is an opinionated plugin tailored for a particular workflow and may not suit general Docusaurus projects

## What is docusaurus.nvim?

`docusaurus.nvim` is a Neovim plugin that enhances your Docusaurus documentation workflow by providing smart insertion of components, partials, code blocks, and URL references. Built on top of telescope.nvim, it offers fuzzy finding capabilities with automatic import management for MDX files.

## Table of contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Commands](#commands)
- [Configuration](#configuration)
- [Usage Examples](#usage-examples)
- [How It Works](#how-it-works)
- [API](#api)
- [License](#license)

## Requirements

- Neovim 0.8.0 or higher
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- Git (for repository root detection)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "Piotr1215/docusaurus.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  "Piotr1215/docusaurus.nvim",
  requires = {
    "nvim-telescope/telescope.nvim",
  },
}
```

## Quick start

1. Install the plugin using your preferred package manager
2. Add the setup call to your Neovim configuration:

```lua
require("docusaurus").setup()
```

3. Set up your preferred keymaps (see [Keymaps](#keymaps) section)

The plugin works out of the box with sensible defaults if your project follows the standard Docusaurus structure.

## Commands

| Command | Description |
|---------|-------------|
| `:DocusaurusInsertComponent` | Browse and insert a component from `src/components` |
| `:DocusaurusInsertPartial` | Browse and insert a partial from `_partials`, `_fragments`, or `_code` directories |
| `:DocusaurusInsertCodeBlock` | Insert a code block with raw-loader import |
| `:DocusaurusInsertURL` | Insert a markdown link to another documentation file |

## Configuration

Call `setup` to configure the plugin:

```lua
require("docusaurus").setup({
  -- Path to your Docusaurus components directory
  -- Default: {git-root}/src/components or ./src/components
  components_dir = "~/your-project/src/components",
  
  -- Directories to search for partials
  -- Default: { "_partials", "_fragments", "_code" }
  partials_dirs = { "_partials", "_fragments", "_code" },
  
  -- Path patterns that are allowed to use @site imports
  -- Default: { "^docs/_partials/", "^docs/_fragments/", "^docs/_code/" }
  -- All other paths will use relative imports
  allowed_site_paths = { "^docs/_partials/", "^docs/_fragments/" },
})
```

### Default configuration

```lua
{
  components_dir = nil, -- auto-detects {git-root}/src/components
  partials_dirs = { "_partials", "_fragments", "_code" },
  allowed_site_paths = { "^docs/_partials/", "^docs/_fragments/", "^docs/_code/" },
}
```

### Keymaps

This plugin doesn't set any default keymaps. You can set your own keymaps like this:

```lua
vim.keymap.set("n", "<leader>ic", "<cmd>DocusaurusInsertComponent<cr>", { desc = "Insert Docusaurus Component" })
vim.keymap.set("n", "<leader>ip", "<cmd>DocusaurusInsertPartial<cr>", { desc = "Insert Docusaurus Partial" })
vim.keymap.set("n", "<leader>ib", "<cmd>DocusaurusInsertCodeBlock<cr>", { desc = "Insert Docusaurus CodeBlock" })
vim.keymap.set("n", "<leader>iu", "<cmd>DocusaurusInsertURL<cr>", { desc = "Insert Docusaurus URL Reference" })
```

## Usage examples

### Insert a component

```markdown
<!-- Before -->
Some content here...

<!-- Press <leader>ic, select "Button" component -->

<!-- After -->
---
title: My Document
---

import Button from '@site/src/components/Button';

Some content here...
<Button />
```

### Insert a code block

```markdown
<!-- Before -->
Here's an example configuration:

<!-- Press <leader>ib, select "config.yaml" from _code directory -->

<!-- After -->
---
title: My Document
---

import CodeBlock from '@theme/CodeBlock';
import ConfigExample from '!!raw-loader!@site/_code/config.yaml';

Here's an example configuration:
<CodeBlock language="yaml" title="Example Config">{ConfigExample}</CodeBlock>
```


## How it works

1. **Components**: When inserting a component, the plugin:
   - Shows a Telescope picker with all component directories
   - Inserts `<ComponentName />` at cursor position
   - Adds `import ComponentName from '@site/src/components/ComponentName';` after the frontmatter

2. **Partials**: When inserting a partial, the plugin:
   - Searches for all `_partials`, `_fragments`, and `_code` directories in your repository
   - Lets you name the import (with a smart default based on filename)
   - Inserts `<PartialName />` at cursor position
   - Adds the appropriate import statement:
     - `@site` imports for non-versioned content (`docs/_partials/`)
     - Relative imports for versioned content

3. **Code Blocks**: When inserting a code block, the plugin:
   - Searches partial directories for code files
   - Inserts `<CodeBlock language="yaml" title="...">{PartialName}</CodeBlock>`
   - Positions cursor between language quotes for easy editing
   - Adds `import CodeBlock from '@theme/CodeBlock'` if not present
   - Adds `import PartialName from '!!raw-loader!@site/path/to/file';`

4. **URL References**: When inserting a URL reference, the plugin:
   - Searches for all `.md` and `.mdx` files in the repository
   - Prompts for link text
   - Inserts `[Link Text](/path/to/doc)` at cursor position

## API

The following functions are available for programmatic use:

```lua
local docusaurus = require("docusaurus")

-- Insert a component
docusaurus.select_component()

-- Insert a partial
docusaurus.select_partial()

-- Insert a code block
docusaurus.select_code_block()

-- Insert a URL reference
docusaurus.insert_url_reference()

-- Get current configuration
local config = docusaurus.get_config()
```

## License

MIT