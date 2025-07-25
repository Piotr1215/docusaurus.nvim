local M = {}

local config = {
  -- Default configuration options
  partials_dirs = { "_partials", "_fragments", "_code" },
  components_dir = nil, -- Will default to ./src/components if not set
  allowed_site_paths = { "^docs/_partials/", "^docs/_fragments/", "^docs/_code/" },
}

function M.setup(user_config)
  -- Merge user config with defaults
  config = vim.tbl_deep_extend("force", config, user_config or {})
end

-- Function to recursively find all _partials directories in the repository
local function get_all_partials_dirs()
  local partials_dirs = {}

  -- Get git repository root
  local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")

  if git_root == "" then
    print "Not inside a git repository."
    return partials_dirs
  end

  local function scan_dir(dir)
    local entries = vim.fn.readdir(dir)
    for _, name in ipairs(entries) do
      local full_path = dir .. "/" .. name
      if vim.fn.isdirectory(full_path) == 1 then
        -- Check if directory name matches any of the configured partial dirs
        for _, partial_dir in ipairs(config.partials_dirs) do
          if name == partial_dir then
            table.insert(partials_dirs, full_path)
            break
          end
        end
        if name ~= "." and name ~= ".." and name ~= ".git" and name ~= "node_modules" then
          scan_dir(full_path)
        end
      end
    end
  end

  scan_dir(git_root)
  return partials_dirs
end

local function get_repository_path(file_path)
  local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")
  return file_path:sub(#git_root + 2) -- +2 to remove leading slash
end

-- Function specifically for code block imports
function M.select_code_block()
  -- Capture the current buffer and window
  local current_bufnr = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()

  -- Get all _partials directories
  local partials_dirs = get_all_partials_dirs()

  if vim.tbl_isempty(partials_dirs) then
    print "No _partials directories found in the repository."
    return
  end

  -- Build find command to exclude markdown files and focus on code files
  local find_command = {
    "find",
  }
  
  -- Add all search directories
  for _, dir in ipairs(partials_dirs) do
    table.insert(find_command, dir)
  end
  
  -- Add conditions to exclude markdown and include code files
  table.insert(find_command, "-type")
  table.insert(find_command, "f")
  table.insert(find_command, "(")
  
  -- Include common code file extensions
  local code_extensions = {
    "*.yaml", "*.yml", "*.json", "*.js", "*.jsx", 
    "*.ts", "*.tsx", "*.sh", "*.bash", "*.py",
    "*.go", "*.rs", "*.toml", "*.xml", "*.conf",
    "*.ini", "*.env", "*.properties", "*.sql"
  }
  
  for i, ext in ipairs(code_extensions) do
    if i > 1 then
      table.insert(find_command, "-o")
    end
    table.insert(find_command, "-name")
    table.insert(find_command, ext)
  end
  
  table.insert(find_command, ")")
  
  -- Exclude markdown files explicitly
  table.insert(find_command, "!")
  table.insert(find_command, "-name")
  table.insert(find_command, "*.md")
  table.insert(find_command, "!")
  table.insert(find_command, "-name") 
  table.insert(find_command, "*.mdx")

  -- Use Telescope to browse code files
  require("telescope.builtin").find_files {
    prompt_title = "Select Code File",
    find_command = find_command,
    layout_strategy = "flex",
    layout_config = {
      flex = {
        flip_columns = 120,  -- Switch to vertical layout on smaller windows
      },
      horizontal = {
        preview_width = 0.35,  -- 35% for preview on the right
        preview_cutoff = 0,
        prompt_position = "top",
        mirror = false,  -- This ensures preview is on the right
      },
      width = 0.95,
      height = 0.85,
    },
    sorting_strategy = "ascending",
    path_display = function(opts, path)
      -- Get the tail (filename) and calculate how much of the path we can show
      local tail = require("telescope.utils").path_tail(path)
      local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")
      
      -- Remove git root from path to make it relative
      local relative_path = path
      if git_root and git_root ~= "" then
        relative_path = path:sub(#git_root + 2) -- +2 to remove the leading slash
      end
      
      -- Return a formatted display with more visible path
      return string.format("%s  [%s]", tail, relative_path)
    end,
    attach_mappings = function(prompt_bufnr, map)
      map("i", "<CR>", function()
        local selection = require("telescope.actions.state").get_selected_entry()
        local partial_path = selection.path

        -- Close Telescope before prompting
        require("telescope.actions").close(prompt_bufnr)

        -- Generate default component name based on the file name
        local partial_name = M.to_camel_case(partial_path)

        -- Prompt for the component name with default value
        partial_name = vim.fn.input("Name the code block: ", partial_name)

        -- Switch back to the original window and buffer
        vim.api.nvim_set_current_win(current_win)
        vim.api.nvim_set_current_buf(current_bufnr)

        -- Insert code block with raw loader
        M.insert_partial_in_buffer(current_bufnr, partial_name, partial_path, true)
      end)
      return true
    end,
  }
end

-- Function to convert a string to CamelCase using only the file name
function M.to_camel_case(str)
  -- Extract the file name without extension
  local file_name = vim.fn.fnamemodify(str, ":t:r")

  local words = {}
  -- Split the file name by hyphens and underscores
  for word in string.gmatch(file_name, "[^%-%_]+") do
    word = word:gsub("^%l", string.upper)
    table.insert(words, word)
  end
  return table.concat(words)
end

-- Function to convert file name to readable text
function M.to_readable_text(str)
  -- Extract the file name without extension
  local file_name = vim.fn.fnamemodify(str, ":t:r")
  -- Replace hyphens and underscores with spaces
  return file_name:gsub("[%-_]", " ")
end

-- Function to get relative path between two absolute paths
local function get_relative_path(from_dir, to_path)
  local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")

  local from_rel = from_dir:sub(#git_root + 2)
  local to_rel = to_path:sub(#git_root + 2)

  local from_parts = vim.split(from_rel, "/")
  local to_parts = vim.split(to_rel, "/")

  local i = 1
  while i <= #from_parts and i <= #to_parts and from_parts[i] == to_parts[i] do
    i = i + 1
  end

  local result = {}
  for _ = i, #from_parts do
    table.insert(result, "..")
  end

  for j = i, #to_parts do
    table.insert(result, to_parts[j])
  end

  return table.concat(result, "/")
end

-- Function to get absolute URL path
local function get_absolute_url_path(file_path)
  -- Get git repository root
  local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")

  -- Remove git root from path and file extension
  local url_path = file_path:sub(#git_root + 2) -- +2 to remove leading slash
  url_path = vim.fn.fnamemodify(url_path, ":r")

  -- Ensure forward slashes
  url_path = url_path:gsub("\\", "/")

  -- Add leading slash
  url_path = "/" .. url_path

  return url_path
end

-- Function to get language identifier from file extension
local function get_language_from_extension(file_path)
  local ext = vim.fn.fnamemodify(file_path, ":e"):lower()
  
  -- Common mappings where the extension doesn't match the language identifier
  local special_mappings = {
    yml = "yaml",
    js = "javascript", 
    ts = "typescript",
    sh = "bash",
    py = "python",
    rs = "rust",
    md = "markdown",
  }
  
  -- Return the special mapping if it exists, otherwise use the extension itself
  return special_mappings[ext] or ext
end

function M.insert_partial_in_buffer(bufnr, partial_name, partial_path, is_raw_loader)
  -- Switch to the buffer
  vim.api.nvim_set_current_buf(bufnr)

  -- Get the cursor position in the correct window
  local cursor_position = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor_position[1]

  local insert_text
  if is_raw_loader then
    -- For raw loader, create CodeBlock component with detected language
    local language = get_language_from_extension(partial_path)
    insert_text = string.format(
      '<CodeBlock language="%s" title="%s">{%s}</CodeBlock>',
      language,
      M.to_readable_text(partial_path),
      partial_name
    )
  else
    -- For regular partials
    insert_text = string.format("<%s />", partial_name)
  end

  -- Insert the component at the cursor position
  vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line - 1, false, { insert_text })

  -- If this is a code block, position cursor at the end of the line
  if is_raw_loader then
    -- Position cursor at the end of the inserted line
    local line_content = vim.api.nvim_buf_get_lines(bufnr, current_line - 1, current_line, false)[1]
    vim.api.nvim_win_set_cursor(0, { current_line, #line_content })
  end

  -- Rest of the function (imports handling) remains the same
  local current_file_path = vim.api.nvim_buf_get_name(bufnr)
  local current_file_dir = vim.fn.fnamemodify(current_file_path, ":h")

  local import_statement
  if is_raw_loader then
    -- Get repository path for checking
    local repo_path = get_repository_path(partial_path)
    
    -- Check if this path is explicitly allowed to use @site
    local use_site_import = false
    for _, allowed_pattern in ipairs(config.allowed_site_paths or {}) do
      if repo_path:match(allowed_pattern) then
        use_site_import = true
        break
      end
    end
    
    if use_site_import then
      -- Use @site for shared non-versioned content only
      import_statement = string.format("import %s from '!!raw-loader!@site/%s';", partial_name, repo_path)
    else
      -- Use relative path for everything else
      local relative_path = get_relative_path(current_file_dir, partial_path)
      import_statement = string.format("import %s from '!!raw-loader!%s';", partial_name, relative_path)
    end
  else
    -- Get repository path for checking
    local repo_path = get_repository_path(partial_path)
    
    -- Check if this path is explicitly allowed to use @site
    local use_site_import = false
    for _, allowed_pattern in ipairs(config.allowed_site_paths or {}) do
      if repo_path:match(allowed_pattern) then
        use_site_import = true
        break
      end
    end
    
    if use_site_import then
      -- Use @site for shared non-versioned content only
      import_statement = string.format("import %s from '@site/%s';", partial_name, repo_path)
    else
      -- Use relative path for everything else
      local relative_path = get_relative_path(current_file_dir, partial_path)
      import_statement = string.format("import %s from '%s';", partial_name, relative_path)
    end
  end

  -- Get the buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local insert_pos = 1
  local found_front_matter_start = false
  local found_front_matter_end = false
  local has_codeblock_import = false

  -- Find the front matter and import section from the top
  for i, line in ipairs(lines) do
    if not found_front_matter_start then
      if line:match "^---$" then
        found_front_matter_start = true
      end
    elseif not found_front_matter_end then
      if line:match "^---$" then
        found_front_matter_end = true
        insert_pos = i + 1
      end
    elseif line:match "^import" then
      insert_pos = i + 1
      if line:match "^import CodeBlock from '@theme/CodeBlock'" then
        has_codeblock_import = true
      end
    end
  end

  -- Insert imports
  local imports = {}
  if is_raw_loader and not has_codeblock_import then
    table.insert(imports, "import CodeBlock from '@theme/CodeBlock'")
  end
  table.insert(imports, import_statement)

  if #imports > 0 then
    table.insert(imports, "") -- Add empty line after imports
    vim.api.nvim_buf_set_lines(bufnr, insert_pos - 1, insert_pos - 1, false, imports)
  end
end

-- Function to insert URL reference at cursor
local function insert_url_reference(bufnr, target_path)
  -- Get URL path
  local url_path = get_absolute_url_path(target_path)

  -- Get the cursor position
  local cursor_position = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor_position[1]

  -- Generate default link text from file name
  local default_text = M.to_readable_text(target_path)

  -- Prompt for link text with default value
  local link_text = vim.fn.input("Enter link text: ", default_text)
  if link_text == "" then
    link_text = default_text
  end

  local markdown_link = string.format("[%s](%s)", link_text, url_path)

  -- Insert the markdown link at cursor position
  local line_content = vim.api.nvim_buf_get_lines(bufnr, current_line - 1, current_line, false)[1]
  local cursor_col = cursor_position[2]

  -- Split the line at cursor position and insert the link
  local new_line = string.sub(line_content, 1, cursor_col) .. markdown_link .. string.sub(line_content, cursor_col + 1)
  vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line, false, { new_line })
end

function M.select_partial()
  -- Capture the current buffer and window
  local current_bufnr = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()

  -- Get all _partials directories
  local partials_dirs = get_all_partials_dirs()

  if vim.tbl_isempty(partials_dirs) then
    print "No _partials directories found in the repository."
    return
  end

  -- Use Telescope to browse partial files
  require("telescope.builtin").find_files {
    prompt_title = "Select Partial",
    search_dirs = partials_dirs,
    layout_strategy = "flex",
    layout_config = {
      flex = {
        flip_columns = 120,  -- Switch to vertical layout on smaller windows
      },
      horizontal = {
        preview_width = 0.35,  -- 35% for preview on the right
        preview_cutoff = 0,
        prompt_position = "top",
        mirror = false,  -- This ensures preview is on the right
      },
      width = 0.95,
      height = 0.85,
    },
    sorting_strategy = "ascending",
    path_display = function(opts, path)
      -- Get the tail (filename) and calculate how much of the path we can show
      local tail = require("telescope.utils").path_tail(path)
      local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")
      
      -- Remove git root from path to make it relative
      local relative_path = path
      if git_root and git_root ~= "" then
        relative_path = path:sub(#git_root + 2) -- +2 to remove the leading slash
      end
      
      -- Return a formatted display with more visible path
      return string.format("%s  [%s]", tail, relative_path)
    end,
    attach_mappings = function(prompt_bufnr, map)
      map("i", "<CR>", function()
        local selection = require("telescope.actions.state").get_selected_entry()
        local partial_path = selection.path

        -- Generate default component name based on the file name
        local partial_name = M.to_camel_case(partial_path)

        -- Prompt for the component name with default value
        partial_name = vim.fn.input("Name the partial: ", partial_name)

        -- Close Telescope before switching back
        require("telescope.actions").close(prompt_bufnr)

        -- Switch back to the original window and buffer
        vim.api.nvim_set_current_win(current_win)
        vim.api.nvim_set_current_buf(current_bufnr)

        -- Insert partial (always as regular import)
        M.insert_partial_in_buffer(current_bufnr, partial_name, partial_path, false)
      end)
      return true
    end,
  }
end

function M.insert_url_reference()
  local current_bufnr = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()

  local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")
  if git_root == "" then
    print "Not inside a git repository."
    return
  end

  -- Change to git root directory
  vim.fn.chdir(git_root)

  require("telescope.builtin").find_files {
    prompt_title = "Select MD(X) File to Reference",
    search_dirs = { "." }, -- Search from current (git root) directory
    find_command = {
      "find",
      ".",
      "-type",
      "f",
      "(",
      "-name",
      "*.md",
      "-o",
      "-name",
      "*.mdx",
      ")",
      "!",
      "-path",
      "*/_*/*",
    },
    layout_strategy = "flex",
    layout_config = {
      flex = {
        flip_columns = 120,  -- Switch to vertical layout on smaller windows
      },
      horizontal = {
        preview_width = 0.35,  -- 35% for preview on the right
        preview_cutoff = 0,
        prompt_position = "top",
        mirror = false,  -- This ensures preview is on the right
      },
      width = 0.95,
      height = 0.85,
    },
    sorting_strategy = "ascending",
    path_display = function(opts, path)
      -- Get the tail (filename) and calculate how much of the path we can show
      local tail = require("telescope.utils").path_tail(path)
      local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")
      
      -- Remove git root from path to make it relative
      local relative_path = path
      if git_root and git_root ~= "" then
        relative_path = path:sub(#git_root + 2) -- +2 to remove the leading slash
      end
      
      -- For URL references, also remove the leading "./"
      if relative_path:sub(1, 2) == "./" then
        relative_path = relative_path:sub(3)
      end
      
      -- Return a formatted display with more visible path
      return string.format("%s  [%s]", tail, relative_path)
    end,
    attach_mappings = function(prompt_bufnr, map)
      map("i", "<CR>", function()
        local selection = require("telescope.actions.state").get_selected_entry()
        local file_path = selection.path
        require("telescope.actions").close(prompt_bufnr)
        vim.api.nvim_set_current_win(current_win)
        vim.api.nvim_set_current_buf(current_bufnr)
        insert_url_reference(current_bufnr, file_path)
      end)
      return true
    end,
  }

  -- Change back to original directory
  vim.fn.chdir "-"
end

-- Function to insert component in buffer
local function insert_component_in_buffer(bufnr, component_name)
  -- Switch to the buffer
  vim.api.nvim_set_current_buf(bufnr)

  -- Get the cursor position in the correct window
  local cursor_position = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor_position[1]

  local component_insert = string.format("<%s />", component_name)

  -- Insert the component at the cursor position
  vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line - 1, false, { component_insert })

  -- Add import statement
  local import_statement = string.format("import %s from '@site/src/components/%s';", component_name, component_name)

  -- Get the buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local insert_pos = 1
  local found_front_matter_start = false
  local found_front_matter_end = false

  -- Find the front matter and import section from the top
  for i, line in ipairs(lines) do
    if not found_front_matter_start then
      if line:match "^---$" then
        found_front_matter_start = true
      end
    elseif not found_front_matter_end then
      if line:match "^---$" then
        found_front_matter_end = true
        insert_pos = i + 1
      end
    elseif line:match "^import" then
      insert_pos = i + 1
    end
  end

  -- Insert the import statement
  vim.api.nvim_buf_set_lines(bufnr, insert_pos - 1, insert_pos - 1, false, { "", import_statement, "" })
end

function M.select_component()
  -- Capture the current buffer and window
  local current_bufnr = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()

  -- Get components directory path from config or use default
  local components_dir = config.components_dir
  
  if not components_dir then
    -- Try to find default components directory relative to git root
    local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")
    if git_root ~= "" then
      components_dir = git_root .. "/src/components"
    else
      -- Fallback to current directory
      components_dir = vim.fn.getcwd() .. "/src/components"
    end
  end
  
  -- Expand ~ if present
  components_dir = vim.fn.expand(components_dir)

  if vim.fn.isdirectory(components_dir) ~= 1 then
    print("Components directory not found at: " .. components_dir)
    return
  end

  -- Get list of component directories
  local components = vim.fn.readdir(components_dir)
  local component_entries = {}

  -- Create entries for telescope
  for _, name in ipairs(components) do
    local full_path = components_dir .. "/" .. name
    if vim.fn.isdirectory(full_path) == 1 then
      table.insert(component_entries, {
        value = name,
        display = name,
        ordinal = name:lower(),
      })
    end
  end

  -- Create picker using Telescope
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  -- Function to get component file content
  local function get_component_content(name)
    local base_path = components_dir .. "/" .. name
    local possible_files = {
      "/index.js",
      "/index.jsx",
      "/" .. name .. ".js",
      "/" .. name .. ".jsx",
    }

    for _, file in ipairs(possible_files) do
      local full_path = base_path .. file
      if vim.fn.filereadable(full_path) == 1 then
        local content = vim.fn.readfile(full_path)
        return table.concat(content, "\n")
      end
    end
    return "No component file found"
  end

  pickers
    .new({}, {
      prompt_title = "Select Component",
      finder = finders.new_table {
        results = component_entries,
        entry_maker = function(entry)
          return {
            value = entry.value,
            display = entry.display,
            ordinal = entry.ordinal,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = require("telescope.previewers").new_buffer_previewer {
        title = "Component Content",
        define_preview = function(self, entry)
          local content = get_component_content(entry.value)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(content, "\n"))

          -- Set filetype for syntax highlighting
          if content:match "%.jsx?$" then
            vim.bo[self.state.bufnr].filetype = "javascriptreact"
          else
            vim.bo[self.state.bufnr].filetype = "javascript"
          end
        end,
      },
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)

          -- Switch back to the original window and buffer
          vim.api.nvim_set_current_win(current_win)
          vim.api.nvim_set_current_buf(current_bufnr)

          -- Insert component
          insert_component_in_buffer(current_bufnr, selection.value)
        end)
        return true
      end,
    })
    :find()
end

-- Export configuration getter for debugging
function M.get_config()
  return config
end

return M