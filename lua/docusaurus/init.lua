local M = {}

local config = {
	-- Default configuration options
	partials_dirs = { "_partials", "_fragments", "_code" },
	components_dir = nil, -- Will default to ./src/components if not set
	allowed_site_paths = { "^docs/_" }, -- Any underscore directory under docs/
}

function M.setup(user_config)
	-- Merge user config with defaults
	config = vim.tbl_deep_extend("force", config, user_config or {})
end

-- ========================================
-- Version Context Functions
-- ========================================

-- Extract version context from file path
-- Returns:
--   { type="versioned", folder="vcluster_versioned_docs/version-0.20.x", project="vcluster" }
--   { type="main", project="vcluster" } (for vcluster/ main folder)
--   { type="non-versioned" } (for shared docs/ folder)
local function get_version_context(file_path, git_root)
	if not file_path or file_path == "" then
		return { type = "non-versioned" }
	end

	-- Make path relative to git root
	local relative_path = file_path
	if git_root and file_path:sub(1, #git_root) == git_root then
		relative_path = file_path:sub(#git_root + 2)
	end

	-- Pattern: <project>_versioned_docs/version-<version>/
	-- Examples: vcluster_versioned_docs/version-0.20.x/, platform_versioned_docs/version-4.4.0/
	local project = relative_path:match("^([^/]+)_versioned_docs/")
	local versioned_folder = relative_path:match("^([^/]+_versioned_docs/version%-[^/]+)")
	if project and versioned_folder then
		return {
			type = "versioned",
			folder = versioned_folder,
			project = project,
		}
	end

	-- Pattern: main project folder (vcluster/, platform/)
	-- These are the current/main version docs
	if relative_path:match("^vcluster/") then
		return {
			type = "main",
			project = "vcluster",
		}
	elseif relative_path:match("^platform/") then
		return {
			type = "main",
			project = "platform",
		}
	end

	return { type = "non-versioned" }
end

-- Check if path matches version context
-- Paths match if they are in:
-- 1. The same version folder (for versioned context)
-- 2. The same main project folder (for main context)
-- 3. Non-versioned root folders (docs/_partials/, docs/_fragments/, docs/_code/)
local function path_matches_context(path, context, git_root)
	if not path or path == "" then
		return false
	end

	-- Make path relative to git root
	local relative_path = path
	if git_root and path:sub(1, #git_root) == git_root then
		relative_path = path:sub(#git_root + 2)
	end

	-- Always include non-versioned root folders (docs/_partials/, etc.)
	for _, pattern in ipairs(config.allowed_site_paths) do
		if relative_path:match(pattern) then
			return true
		end
	end

	-- If no specific version/project context, show all
	if context.type == "non-versioned" then
		return true
	end

	-- If main project context (vcluster/, platform/), only show:
	-- - Files from the same project's main folder
	-- - NOT from versioned folders or other projects
	if context.type == "main" and context.project then
		-- Check if path is in same main project folder
		if relative_path:match("^" .. context.project .. "/") then
			return true
		end
		-- Exclude versioned folders and other projects
		return false
	end

	-- If versioned context, only show files from same version folder
	if context.type == "versioned" and context.folder then
		return relative_path:sub(1, #context.folder) == context.folder
	end

	return false
end

-- Function to recursively find all _partials directories in the repository
-- Optional: filter by version context
local function get_all_partials_dirs(version_context, git_root_param)
	local partials_dirs = {}

	-- Get git repository root
	local git_root = git_root_param or vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")

	if git_root == "" then
		print("Not inside a git repository.")
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
						-- Apply version context filtering if provided
						if not version_context or path_matches_context(full_path, version_context, git_root) then
							table.insert(partials_dirs, full_path)
						end
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

	-- Sort partials: root docs folders first, then version-specific folders
	table.sort(partials_dirs, function(a, b)
		local a_rel = a:sub(#git_root + 2) -- Remove git root prefix
		local b_rel = b:sub(#git_root + 2)

		-- Check if paths match allowed_site_paths patterns (root docs folders)
		local a_is_root = false
		local b_is_root = false
		for _, pattern in ipairs(config.allowed_site_paths) do
			if a_rel:match(pattern) then
				a_is_root = true
			end
			if b_rel:match(pattern) then
				b_is_root = true
			end
		end

		-- Root folders come first
		if a_is_root and not b_is_root then
			return true
		end
		if b_is_root and not a_is_root then
			return false
		end

		-- Otherwise alphabetical
		return a < b
	end)

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

	-- Get current file path and version context
	local current_file = vim.api.nvim_buf_get_name(current_bufnr)
	local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")
	local version_context = get_version_context(current_file, git_root)

	-- Get filtered _partials directories based on version context
	local partials_dirs = get_all_partials_dirs(version_context, git_root)

	if vim.tbl_isempty(partials_dirs) then
		print("No _partials directories found in the repository.")
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
		"*.yaml",
		"*.yml",
		"*.json",
		"*.js",
		"*.jsx",
		"*.ts",
		"*.tsx",
		"*.sh",
		"*.bash",
		"*.py",
		"*.go",
		"*.rs",
		"*.toml",
		"*.xml",
		"*.conf",
		"*.ini",
		"*.env",
		"*.properties",
		"*.sql",
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
	require("telescope.builtin").find_files({
		prompt_title = "Select Code File",
		find_command = find_command,
		layout_strategy = "flex",
		layout_config = {
			flex = {
				flip_columns = 120, -- Switch to vertical layout on smaller windows
			},
			horizontal = {
				preview_width = 0.35, -- 35% for preview on the right
				preview_cutoff = 0,
				prompt_position = "top",
				mirror = false, -- This ensures preview is on the right
			},
			width = 0.95,
			height = 0.85,
		},
		sorting_strategy = "ascending",
		path_display = function(opts, path)
			-- Get the tail (filename) and calculate how much of the path we can show
			local tail = require("telescope.utils").path_tail(path)
			local local_git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")

			-- Remove git root from path to make it relative
			local relative_path = path
			if local_git_root and local_git_root ~= "" then
				relative_path = path:sub(#local_git_root + 2) -- +2 to remove the leading slash
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
	})
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

-- Function to convert string to camelCase (first letter lowercase, for function names)
local function to_camel_case_lower(str)
	local pascal = M.to_camel_case(str)
	-- Convert first letter to lowercase
	return pascal:sub(1, 1):lower() .. pascal:sub(2)
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

	-- Check if import already exists
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local import_exists = false
	for _, line in ipairs(lines) do
		if line:match("^import") then
			local import_name = line:match("^import%s+(%S+)%s+from")
			if import_name == partial_name then
				import_exists = true
				break
			end
		end
	end

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

	-- Position cursor on the inserted component tag
	local line_content = vim.api.nvim_buf_get_lines(bufnr, current_line - 1, current_line, false)[1]
	-- Find the position of '<' in the inserted line
	local tag_start = line_content:find("<")
	if tag_start then
		vim.api.nvim_win_set_cursor(0, { current_line, tag_start - 1 })
	end

	-- If import already exists, skip adding it
	if import_exists then
		return
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

	-- Get the buffer lines again (for import insertion)
	lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local insert_pos = 1
	local found_front_matter_start = false
	local found_front_matter_end = false
	local has_codeblock_import = false

	-- Find the front matter and import section from the top
	for i, line in ipairs(lines) do
		if not found_front_matter_start then
			if line:match("^---$") then
				found_front_matter_start = true
			end
		elseif not found_front_matter_end then
			if line:match("^---$") then
				found_front_matter_end = true
				insert_pos = i + 1
			end
		elseif line:match("^import") then
			insert_pos = i + 1
			if line:match("^import CodeBlock from '@theme/CodeBlock'") then
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
	-- Get current file directory
	local current_file_path = vim.api.nvim_buf_get_name(bufnr)
	local current_file_dir = vim.fn.fnamemodify(current_file_path, ":h")

	-- Get relative path from current file to target, without extension
	local url_path = get_relative_path(current_file_dir, target_path)
	-- Remove file extension for clean URLs
	url_path = vim.fn.fnamemodify(url_path, ":r")

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
	local new_line = string.sub(line_content, 1, cursor_col)
		.. markdown_link
		.. string.sub(line_content, cursor_col + 1)
	vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line, false, { new_line })
end

function M.select_partial()
	-- Capture the current buffer and window
	local current_bufnr = vim.api.nvim_get_current_buf()
	local current_win = vim.api.nvim_get_current_win()

	-- Get current file path and version context
	local current_file = vim.api.nvim_buf_get_name(current_bufnr)
	local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")
	local version_context = get_version_context(current_file, git_root)

	-- Get filtered _partials directories based on version context
	local partials_dirs = get_all_partials_dirs(version_context, git_root)

	if vim.tbl_isempty(partials_dirs) then
		print("No _partials directories found in the repository.")
		return
	end

	-- Collect all partial files and sort them
	local all_files = {}
	for _, dir in ipairs(partials_dirs) do
		local function scan_files(directory)
			local entries = vim.fn.readdir(directory)
			for _, name in ipairs(entries) do
				local full_path = directory .. "/" .. name
				if vim.fn.isdirectory(full_path) == 1 then
					scan_files(full_path)
				elseif name:match("%.mdx?$") then
					-- Check if file is from root docs folder
					local relative_path = full_path:sub(#git_root + 2)
					local is_root = false
					for _, pattern in ipairs(config.allowed_site_paths) do
						if relative_path:match(pattern) then
							is_root = true
							break
						end
					end
					table.insert(all_files, {
						path = full_path,
						is_root = is_root,
						relative_path = relative_path,
					})
				end
			end
		end
		scan_files(dir)
	end

	-- Sort: root docs files first, then alphabetically
	table.sort(all_files, function(a, b)
		if a.is_root and not b.is_root then
			return true
		end
		if b.is_root and not a.is_root then
			return false
		end
		return a.path < b.path
	end)

	-- Use Telescope with custom picker
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	pickers
		.new({}, {
			prompt_title = "Select Partial",
			finder = finders.new_table({
				results = all_files,
				entry_maker = function(entry)
					local tail = require("telescope.utils").path_tail(entry.path)
					local display = string.format("%s  [%s]", tail, entry.relative_path)
					return {
						value = entry.path,
						display = display,
						ordinal = entry.path,
						path = entry.path,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = conf.file_previewer({}),
			layout_strategy = "flex",
			layout_config = {
				flex = {
					flip_columns = 120,
				},
				horizontal = {
					preview_width = 0.35,
					preview_cutoff = 0,
					prompt_position = "top",
					mirror = false,
				},
				width = 0.95,
				height = 0.85,
			},
			sorting_strategy = "ascending",
			attach_mappings = function(prompt_bufnr, map)
				map("i", "<CR>", function()
					local selection = action_state.get_selected_entry()
					local partial_path = selection.path

					-- Generate default component name based on the file name
					local partial_name = M.to_camel_case(partial_path)

					-- Prompt for the component name with default value
					partial_name = vim.fn.input("Name the partial: ", partial_name)

					-- Close Telescope before switching back
					actions.close(prompt_bufnr)

					-- Switch back to the original window and buffer
					vim.api.nvim_set_current_win(current_win)
					vim.api.nvim_set_current_buf(current_bufnr)

					-- Insert partial (always as regular import)
					M.insert_partial_in_buffer(current_bufnr, partial_name, partial_path, false)
				end)
				return true
			end,
		})
		:find()
end

function M.insert_url_reference()
	local current_bufnr = vim.api.nvim_get_current_buf()
	local current_win = vim.api.nvim_get_current_win()

	local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")
	if git_root == "" then
		print("Not inside a git repository.")
		return
	end

	-- Get current file path and version context
	local current_file = vim.api.nvim_buf_get_name(current_bufnr)
	local version_context = get_version_context(current_file, git_root)

	-- Build search paths based on version context
	local search_paths = {}
	if version_context.type == "versioned" and version_context.folder then
		-- Add version-specific folder only
		-- URLs should only reference docs from the same version
		table.insert(search_paths, git_root .. "/" .. version_context.folder)
	elseif version_context.type == "main" and version_context.project then
		-- Add main project folder only
		-- URLs should only reference docs from the same project
		table.insert(search_paths, git_root .. "/" .. version_context.project)
	else
		-- No version/project context, search entire git root
		search_paths = { git_root }
	end

	-- Use Lua to collect matching files from search paths
	local function collect_md_files()
		local files = {}
		for _, search_path in ipairs(search_paths) do
			local function scan_dir(dir)
				local entries = vim.fn.readdir(dir)
				for _, name in ipairs(entries) do
					local full_path = dir .. "/" .. name
					if vim.fn.isdirectory(full_path) == 1 then
						-- Skip underscore directories
						if not name:match("^_") and name ~= ".git" and name ~= "node_modules" then
							scan_dir(full_path)
						end
					elseif name:match("%.mdx?$") then
						table.insert(files, full_path)
					end
				end
			end
			if vim.fn.isdirectory(search_path) == 1 then
				scan_dir(search_path)
			end
		end
		return files
	end

	local md_files = collect_md_files()

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	pickers
		.new({}, {
			prompt_title = "Select MD(X) File to Reference",
			finder = finders.new_table({
				results = md_files,
				entry_maker = function(entry)
					local display_path = entry
					if git_root and entry:sub(1, #git_root) == git_root then
						display_path = entry:sub(#git_root + 2)
					end
					return {
						value = entry,
						display = display_path,
						ordinal = display_path,
						path = entry,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = conf.file_previewer({}),
			layout_strategy = "flex",
			layout_config = {
				flex = {
					flip_columns = 120, -- Switch to vertical layout on smaller windows
				},
				horizontal = {
					preview_width = 0.35, -- 35% for preview on the right
					preview_cutoff = 0,
					prompt_position = "top",
					mirror = false, -- This ensures preview is on the right
				},
				width = 0.95,
				height = 0.85,
			},
			sorting_strategy = "ascending",
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					local file_path = selection.path
					actions.close(prompt_bufnr)
					vim.api.nvim_set_current_win(current_win)
					vim.api.nvim_set_current_buf(current_bufnr)
					insert_url_reference(current_bufnr, file_path)
				end)
				return true
			end,
		})
		:find()
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
			if line:match("^---$") then
				found_front_matter_start = true
			end
		elseif not found_front_matter_end then
			if line:match("^---$") then
				found_front_matter_end = true
				insert_pos = i + 1
			end
		elseif line:match("^import") then
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
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

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
			finder = finders.new_table({
				results = component_entries,
				entry_maker = function(entry)
					return {
						value = entry.value,
						display = entry.display,
						ordinal = entry.ordinal,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = require("telescope.previewers").new_buffer_previewer({
				title = "Component Content",
				define_preview = function(self, entry)
					local content = get_component_content(entry.value)
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(content, "\n"))

					-- Set filetype for syntax highlighting
					if content:match("%.jsx?$") then
						vim.bo[self.state.bufnr].filetype = "javascriptreact"
					else
						vim.bo[self.state.bufnr].filetype = "javascript"
					end
				end,
			}),
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

-- ========================================
-- Plugin Scaffolder Functions
-- ========================================

-- Generate plugin template based on type
function M.generate_plugin_template(opts)
	local name = opts.name or "my-plugin"
	local plugin_type = opts.type or "lifecycle"

	local camel_name = to_camel_case_lower(name)

	if plugin_type == "lifecycle" then
		return string.format(
			[[module.exports = function %s(context, options) {
  return {
    name: '%s',

    async loadContent() {
      // Load data from source
    },

    async contentLoaded({content, actions}) {
      // Create routes and process content
    },

    async postBuild({siteConfig, routesPaths, outDir, head}) {
      // Execute after the production build
    },

    async postStart({siteConfig}) {
      // Execute after the dev server starts
    },
  };
};
]],
			camel_name,
			name
		)
	elseif plugin_type == "content" then
		return string.format(
			[[module.exports = function %s(context, options) {
  return {
    name: '%s',

    async loadContent() {
      // Load content from files/API
      return {
        /* your content data */
      };
    },

    async contentLoaded({content, actions}) {
      const {createData, addRoute} = actions;

      // Create pages/routes
      const data = await createData('data.json', JSON.stringify(content));

      addRoute({
        path: '/%s',
        component: '@site/src/components/%sPage.js',
        modules: {
          data,
        },
        exact: true,
      });
    },
  };
};
]],
			camel_name,
			name,
			name,
			camel_name
		)
	elseif plugin_type == "theme" then
		return string.format(
			[[module.exports = function %s(context, options) {
  return {
    name: '%s',

    getThemePath() {
      return './theme';
    },

    getTypeScriptThemePath() {
      return './src/theme';
    },

    getClientModules() {
      return ['./customCss.css'];
    },
  };
};
]],
			camel_name,
			name
		)
	end

	return ""
end

-- Scaffold a new plugin with directory structure
function M.scaffold_plugin(opts)
	local name = opts.name or "my-plugin"
	local plugin_type = opts.type or "lifecycle"
	local write_file = opts.write_file -- For testing

	local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")
	if git_root == "" then
		git_root = vim.fn.getcwd()
	end

	local plugin_dir = git_root .. "/plugins/" .. name

	-- Create directory
	vim.fn.mkdir(plugin_dir, "p")

	-- Generate template
	local template = M.generate_plugin_template({ name = name, type = plugin_type })

	-- Write index.js
	local index_path = plugin_dir .. "/index.js"
	if write_file then
		write_file(index_path, template)
	else
		local file = io.open(index_path, "w")
		if file then
			file:write(template)
			file:close()
		end
	end

	-- Create package.json
	local package_json = string.format(
		[[{
  "name": "%s",
  "version": "0.0.1",
  "description": "A Docusaurus plugin",
  "main": "index.js",
  "dependencies": {}
}
]],
		name
	)

	local package_path = plugin_dir .. "/package.json"
	if write_file then
		write_file(package_path, package_json)
	else
		local file = io.open(package_path, "w")
		if file then
			file:write(package_json)
			file:close()
		end
	end

	print(string.format("Plugin scaffolded at: %s", plugin_dir))
	return plugin_dir
end

-- Interactive plugin scaffolder command
function M.create_plugin()
	local name = vim.fn.input("Plugin name: ", "my-plugin")
	if name == "" then
		return
	end

	local type_choice = vim.fn.confirm("Select plugin type:", "&Lifecycle\n&Content\n&Theme", 1)

	local plugin_types = { "lifecycle", "content", "theme" }
	local plugin_type = plugin_types[type_choice] or "lifecycle"

	M.scaffold_plugin({ name = name, type = plugin_type })
end

-- ========================================
-- API Browser Functions
-- ========================================

-- Get Docusaurus version from package.json
function M.get_docusaurus_version()
	local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")
	if git_root == "" then
		git_root = vim.fn.getcwd()
	end

	local package_path = git_root .. "/package.json"
	if vim.fn.filereadable(package_path) ~= 1 then
		return nil
	end

	local lines = vim.fn.readfile(package_path)
	local content = table.concat(lines, "\n")

	-- Try to find @docusaurus/core version
	local version = content:match('"@docusaurus/core"%s*:%s*"[%^~]?([%d%.]+)"')

	return version
end

-- Get configuration options for a Docusaurus version
-- Fetch and parse Docusaurus config options from GitHub
function M.get_config_options(version, mock_content)
	local content = mock_content

	-- Fetch from GitHub if no mock content provided
	if not content then
		local url =
			"https://raw.githubusercontent.com/facebook/docusaurus/main/website/docs/api/docusaurus.config.js.mdx"

		-- Try curl first (Linux/Mac/WSL), then wget (fallback), then PowerShell (Windows)
		local fetch_commands = {
			string.format("curl -sL '%s'", url),
			string.format("wget -qO- '%s'", url),
			string.format(
				"powershell -Command \"Invoke-WebRequest -Uri '%s' -UseBasicParsing | Select-Object -ExpandProperty Content\"",
				url
			),
		}

		for _, cmd in ipairs(fetch_commands) do
			content = vim.fn.system(cmd)
			if vim.v.shell_error == 0 and content ~= "" then
				break
			end
		end

		if vim.v.shell_error ~= 0 or content == "" then
			print("Failed to fetch Docusaurus config documentation from GitHub")
			print("Please ensure curl, wget, or PowerShell is available")
			return {}
		end
	end

	local options = {}

	-- Parse markdown structure: ### `optionName` {#anchor}
	-- Followed by: - Type: `type`
	-- Then description and examples
	local current_option = nil
	local in_description = false
	local in_example = false
	local example_lines = {}

	for line in content:gmatch("[^\r\n]+") do
		-- Match config option heading: ### `optionName` {#anchor}
		local option_name, anchor = line:match("^###%s+`([^`]+)`%s+{#([^}]+)}")
		if option_name and anchor then
			-- Save previous option if exists
			if current_option then
				current_option.example = table.concat(example_lines, "\n")
				table.insert(options, current_option)
			end

			-- Start new option
			current_option = {
				name = option_name,
				anchor = anchor,
				type = "unknown",
				description = "",
				example = "",
				url = "https://docusaurus.io/docs/api/docusaurus-config#" .. anchor,
			}
			in_description = false
			in_example = false
			example_lines = {}
		elseif current_option then
			-- Match type: - Type: `type`
			local type_str = line:match("^%-%s+Type:%s+`([^`]+)`")
			if type_str then
				current_option.type = type_str
				in_description = true
			-- Match code block start for examples
			elseif line:match("^```") then
				if in_example then
					in_example = false
				else
					in_example = true
				end
			-- Collect example lines
			elseif in_example then
				table.insert(example_lines, line)
			-- Collect description lines (first paragraph after type)
			elseif in_description and line ~= "" and not line:match("^```") and not line:match("^%-%s+Type:") then
				if current_option.description == "" then
					current_option.description = line
				end
			end
		end
	end

	-- Save last option
	if current_option then
		current_option.example = table.concat(example_lines, "\n")
		table.insert(options, current_option)
	end

	return options
end

-- Browse Docusaurus API options using Telescope
function M.browse_api()
	local version = M.get_docusaurus_version()
	if not version then
		print("Could not detect Docusaurus version from package.json")
		version = "3.0.0" -- Default
	end

	local options = M.get_config_options(version)

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")

	pickers
		.new({}, {
			prompt_title = string.format("Docusaurus Config Options (v%s)", version),
			finder = finders.new_table({
				results = options,
				entry_maker = function(entry)
					return {
						value = entry,
						display = string.format("%s (%s)", entry.name, entry.type),
						ordinal = entry.name:lower(),
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				title = "Option Details",
				define_preview = function(self, entry)
					local option = entry.value

					-- Split example into lines if it contains newlines
					local example_lines = {}
					if option.example and option.example ~= "" then
						for line in option.example:gmatch("[^\r\n]+") do
							table.insert(example_lines, line)
						end
					end

					local lines = {
						"Name: " .. option.name,
						"Type: " .. option.type,
						"",
						"Description:",
						option.description,
						"",
						"Documentation:",
						option.url or "N/A",
						"",
						"Example:",
					}

					-- Append example lines
					for _, line in ipairs(example_lines) do
						table.insert(lines, line)
					end

					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
					vim.bo[self.state.bufnr].filetype = "javascript"
				end,
			}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					local option = selection.value
					actions.close(prompt_bufnr)

					-- Open browser to the config option's documentation
					if option.url then
						local open_cmd
						if vim.fn.has("mac") == 1 then
							open_cmd = "open"
						elseif vim.fn.has("unix") == 1 then
							open_cmd = "xdg-open"
						elseif vim.fn.has("win32") == 1 then
							open_cmd = "start"
						end

						if open_cmd then
							vim.fn.system(string.format("%s '%s'", open_cmd, option.url))
							print(string.format("Opening documentation: %s", option.url))
						end
					end
				end)
				return true
			end,
		})
		:find()
end

-- Expose internal functions for testing
M.get_version_context = get_version_context
M.path_matches_context = path_matches_context

return M
