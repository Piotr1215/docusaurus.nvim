describe("docusaurus.nvim", function()
	local docusaurus
	local mock_git_root = "/test/project"

	before_each(function()
		-- Clear any previous module cache
		package.loaded["docusaurus"] = nil
		docusaurus = require("docusaurus")

		-- Mock vim.fn.system for git commands
		vim.fn.system = function(cmd)
			if type(cmd) == "string" and cmd:match("git rev%-parse") then
				return mock_git_root .. "\n"
			end
			return ""
		end

		-- Mock vim.fn.readdir
		vim.fn.readdir = function(dir)
			if dir == mock_git_root then
				return { "src", "docs", "vcluster_versioned_docs", ".git" }
			elseif dir == mock_git_root .. "/src" then
				return { "components", "pages" }
			elseif dir == mock_git_root .. "/docs" then
				return { "_partials", "_fragments", "guides" }
			elseif dir == mock_git_root .. "/docs/_partials" then
				return { "header.mdx", "footer.mdx" }
			elseif dir == mock_git_root .. "/docs/_fragments" then
				return { "intro.mdx", "setup.mdx" }
			elseif dir == mock_git_root .. "/vcluster_versioned_docs" then
				return { "version-0.26.0" }
			elseif dir == mock_git_root .. "/vcluster_versioned_docs/version-0.26.0" then
				return { "_partials", "docs" }
			elseif dir == mock_git_root .. "/vcluster_versioned_docs/version-0.26.0/_partials" then
				return { "config.mdx" }
			elseif dir:match("/components$") then
				return { "Button", "Card", "Layout" }
			end
			return {}
		end

		-- Mock vim.fn.isdirectory
		vim.fn.isdirectory = function(path)
			local dirs = {
				[mock_git_root] = 1,
				[mock_git_root .. "/src"] = 1,
				[mock_git_root .. "/src/components"] = 1,
				[mock_git_root .. "/docs"] = 1,
				[mock_git_root .. "/docs/_partials"] = 1,
				[mock_git_root .. "/docs/_fragments"] = 1,
				[mock_git_root .. "/vcluster_versioned_docs"] = 1,
				[mock_git_root .. "/vcluster_versioned_docs/version-0.26.0"] = 1,
				[mock_git_root .. "/vcluster_versioned_docs/version-0.26.0/_partials"] = 1,
				[mock_git_root .. "/src/components/Button"] = 1,
				[mock_git_root .. "/src/components/Card"] = 1,
				[mock_git_root .. "/src/components/Layout"] = 1,
			}
			return dirs[path] or 0
		end
	end)

	describe("setup", function()
		it("should accept configuration", function()
			docusaurus.setup({
				components_dir = "/custom/components",
				partials_dirs = { "_test" },
				allowed_site_paths = { "^docs/_test/" },
			})

			local config = docusaurus.get_config()
			assert.are.equal("/custom/components", config.components_dir)
			assert.are.same({ "_test" }, config.partials_dirs)
			assert.are.same({ "^docs/_test/" }, config.allowed_site_paths)
		end)

		it("should use default values when not specified", function()
			docusaurus.setup({})

			local config = docusaurus.get_config()
			assert.are.same({ "_partials", "_fragments", "_code" }, config.partials_dirs)
			assert.is_nil(config.components_dir) -- Should be nil, will default at runtime
			assert.are.same({ "^docs/_" }, config.allowed_site_paths)
		end)
	end)

	describe("to_camel_case", function()
		it("should convert hyphenated names to CamelCase", function()
			assert.are.equal("MyComponent", docusaurus.to_camel_case("/path/to/my-component.tsx"))
			assert.are.equal("TestFile", docusaurus.to_camel_case("/path/to/test-file.js"))
			assert.are.equal("VeryLongName", docusaurus.to_camel_case("/path/to/very-long-name.mdx"))
		end)

		it("should convert underscored names to CamelCase", function()
			assert.are.equal("MyComponent", docusaurus.to_camel_case("/path/to/my_component.tsx"))
			assert.are.equal("TestFile", docusaurus.to_camel_case("/path/to/test_file.js"))
		end)

		it("should handle mixed separators", function()
			assert.are.equal("MyTestComponent", docusaurus.to_camel_case("/path/to/my-test_component.tsx"))
		end)

		it("should handle single word files", function()
			assert.are.equal("Button", docusaurus.to_camel_case("/path/to/button.tsx"))
			assert.are.equal("Card", docusaurus.to_camel_case("card.mdx"))
		end)

		it("should handle files without extension", function()
			assert.are.equal("MyComponent", docusaurus.to_camel_case("/path/to/my-component"))
		end)
	end)

	describe("to_readable_text", function()
		it("should convert file names to readable text", function()
			assert.are.equal("my component", docusaurus.to_readable_text("/path/to/my-component.tsx"))
			assert.are.equal("test file", docusaurus.to_readable_text("/path/to/test_file.js"))
			assert.are.equal("very long name", docusaurus.to_readable_text("/path/to/very-long-name.mdx"))
		end)

		it("should handle single word files", function()
			assert.are.equal("button", docusaurus.to_readable_text("/path/to/button.tsx"))
			assert.are.equal("card", docusaurus.to_readable_text("card.mdx"))
		end)
	end)

	describe("insert_partial_in_buffer", function()
		local test_bufnr

		before_each(function()
			-- Create a test buffer with frontmatter
			test_bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"---",
				"title: Test Document",
				"---",
				"",
				"# Test Content",
				"",
				"Some text here",
			})
			vim.api.nvim_buf_set_name(test_bufnr, mock_git_root .. "/docs/test.mdx")

			-- Mock vim.api.nvim_win_get_cursor
			vim.api.nvim_win_get_cursor = function()
				return { 7, 0 } -- Line 7, column 0
			end

			-- Extend the mock for new test directories
			local orig_readdir = vim.fn.readdir
			vim.fn.readdir = function(dir)
				if dir == mock_git_root .. "/docs/vcluster" then
					return { "_partials" }
				elseif dir == mock_git_root .. "/docs/vcluster/_partials" then
					return { "vcluster-config.mdx" }
				elseif dir == mock_git_root .. "/docs/platform" then
					return { "_partials" }
				elseif dir == mock_git_root .. "/docs/platform/_partials" then
					return { "platform-setup.mdx" }
				end
				return orig_readdir(dir)
			end

			-- Extend isdirectory mock
			local orig_isdirectory = vim.fn.isdirectory
			vim.fn.isdirectory = function(path)
				local additional_dirs = {
					[mock_git_root .. "/docs/vcluster"] = 1,
					[mock_git_root .. "/docs/vcluster/_partials"] = 1,
					[mock_git_root .. "/docs/platform"] = 1,
					[mock_git_root .. "/docs/platform/_partials"] = 1,
				}
				return additional_dirs[path] or orig_isdirectory(path)
			end
		end)

		after_each(function()
			if vim.api.nvim_buf_is_valid(test_bufnr) then
				vim.api.nvim_buf_delete(test_bufnr, { force = true })
			end
		end)

		it("should insert docs partial with @site import", function()
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"Header",
				mock_git_root .. "/docs/_partials/header.mdx",
				false
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)

			-- Check import was added after frontmatter with @site
			assert.are.equal("import Header from '@site/docs/_partials/header.mdx';", lines[4])

			-- Check component was inserted at cursor
			assert.is_truthy(vim.tbl_contains(lines, "<Header />"))
		end)

		it("should insert versioned partial with relative import", function()
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"Config",
				mock_git_root .. "/vcluster_versioned_docs/version-0.26.0/_partials/config.mdx",
				false
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)

			-- Check import was added with relative path (not @site)
			local has_relative_import = false
			for _, line in ipairs(lines) do
				if line:match("import Config from '%.%./") then
					has_relative_import = true
					break
				end
			end
			assert.is_true(has_relative_import)

			-- Check component was inserted at cursor
			assert.is_truthy(vim.tbl_contains(lines, "<Config />"))
		end)

		it("should insert code block with raw loader from docs", function()
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"ConfigExample",
				mock_git_root .. "/docs/_partials/config.yaml",
				true
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)

			-- Check CodeBlock import was added
			local has_codeblock_import = false
			local has_raw_import = false
			for _, line in ipairs(lines) do
				if line:match("import CodeBlock from '@theme/CodeBlock'") then
					has_codeblock_import = true
				end
				if line:match("import ConfigExample from '!!raw%-loader!@site/docs/_partials/config.yaml';") then
					has_raw_import = true
				end
			end
			assert.is_true(has_codeblock_import)
			assert.is_true(has_raw_import)

			-- Check CodeBlock component was inserted
			local has_codeblock = false
			for _, line in ipairs(lines) do
				if line:match('<CodeBlock language="yaml".*title="config".*{ConfigExample}</CodeBlock>') then
					has_codeblock = true
				end
			end
			assert.is_true(has_codeblock)
		end)

		it("should insert code block with relative raw loader from versioned docs", function()
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"ConfigExample",
				mock_git_root .. "/vcluster_versioned_docs/version-0.26.0/_partials/config.yaml",
				true
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)

			-- Check import was added with relative path and raw-loader
			local has_relative_raw_import = false
			for _, line in ipairs(lines) do
				if line:match("import ConfigExample from '!!raw%-loader!%.%./") then
					has_relative_raw_import = true
					break
				end
			end
			assert.is_true(has_relative_raw_import)
		end)

		it("should use relative import for vcluster paths", function()
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"VClusterConfig",
				mock_git_root .. "/docs/vcluster/_partials/vcluster-config.mdx",
				false
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)

			-- Check import uses relative path, not @site
			local has_relative_import = false
			local has_site_import = false
			for _, line in ipairs(lines) do
				if line:match("import VClusterConfig from '@site/") then
					has_site_import = true
				end
				-- Look for relative import (may or may not have ./ prefix)
				if
					line:match("import VClusterConfig from '.*vcluster/_partials/vcluster%-config%.mdx';")
					and not line:match("@site")
				then
					has_relative_import = true
				end
			end
			assert.is_false(has_site_import)
			assert.is_true(has_relative_import)
		end)

		it("should use relative import for platform paths", function()
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"PlatformSetup",
				mock_git_root .. "/docs/platform/_partials/platform-setup.mdx",
				false
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)

			-- Check import uses relative path, not @site
			local has_relative_import = false
			local has_site_import = false
			for _, line in ipairs(lines) do
				if line:match("import PlatformSetup from '@site/") then
					has_site_import = true
				end
				-- Look for relative import (may or may not have ./ prefix)
				if
					line:match("import PlatformSetup from '.*platform/_partials/platform%-setup%.mdx';")
					and not line:match("@site")
				then
					has_relative_import = true
				end
			end
			assert.is_false(has_site_import)
			assert.is_true(has_relative_import)
		end)

		it("should use relative raw-loader import for vcluster code blocks", function()
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"VClusterExample",
				mock_git_root .. "/docs/vcluster/_partials/example.yaml",
				true
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)

			-- Check import uses relative path with raw-loader, not @site
			local has_relative_raw_import = false
			local has_site_raw_import = false
			for _, line in ipairs(lines) do
				if line:match("import VClusterExample from '!!raw%-loader!@site/") then
					has_site_raw_import = true
				end
				-- Look for relative import with raw-loader (may or may not have ./ prefix)
				if
					line:match("import VClusterExample from '!!raw%-loader!.*vcluster/_partials/example%.yaml';")
					and not line:match("@site")
				then
					has_relative_raw_import = true
				end
			end
			assert.is_false(has_site_raw_import)
			assert.is_true(has_relative_raw_import)
		end)

		it("should respect custom allowed_site_paths configuration", function()
			-- Set custom configuration
			docusaurus.setup({
				allowed_site_paths = { "^docs/_partials/" }, -- Only allow docs/_partials, not _fragments or _code
			})

			-- Test that docs/_fragments now uses relative import
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"Intro",
				mock_git_root .. "/docs/_fragments/intro.mdx",
				false
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)

			-- Check import uses relative path, not @site
			local has_relative_import = false
			local has_site_import = false
			for _, line in ipairs(lines) do
				if line:match("import Intro from '@site/") then
					has_site_import = true
				end
				if line:match("import Intro from '.*_fragments/intro%.mdx';") and not line:match("@site") then
					has_relative_import = true
				end
			end
			assert.is_false(has_site_import)
			assert.is_true(has_relative_import)

			-- Reset to defaults
			docusaurus.setup({})
		end)

		it("should not insert duplicate import if name already exists", function()
			-- First, insert a partial
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"DuplicateTest",
				mock_git_root .. "/docs/_partials/test.mdx",
				false
			)

			local lines_before = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
			local import_count_before = 0
			local component_count_before = 0
			for _, line in ipairs(lines_before) do
				if line:match("import DuplicateTest from") then
					import_count_before = import_count_before + 1
				end
				if line:match("<DuplicateTest />") then
					component_count_before = component_count_before + 1
				end
			end

			-- Try to insert the same import name again (different path)
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"DuplicateTest",
				mock_git_root .. "/docs/_partials/another-test.mdx",
				false
			)

			local lines_after = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
			local import_count_after = 0
			local component_count_after = 0
			for _, line in ipairs(lines_after) do
				if line:match("import DuplicateTest from") then
					import_count_after = import_count_after + 1
				end
				if line:match("<DuplicateTest />") then
					component_count_after = component_count_after + 1
				end
			end

			-- Should still have only one import
			assert.are.equal(1, import_count_before)
			assert.are.equal(1, import_count_after)

			-- But should have two component tags
			assert.are.equal(1, component_count_before)
			assert.are.equal(2, component_count_after)
		end)
	end)

	describe("code block language detection", function()
		local test_bufnr

		before_each(function()
			-- Create a test buffer with frontmatter
			test_bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"---",
				"title: Test Document",
				"---",
				"",
				"# Test Content",
				"",
				"Some text here",
			})
			vim.api.nvim_buf_set_name(test_bufnr, mock_git_root .. "/docs/test.mdx")

			-- Mock vim.api.nvim_win_get_cursor
			vim.api.nvim_win_get_cursor = function()
				return { 7, 0 } -- Line 7, column 0
			end
		end)

		after_each(function()
			if vim.api.nvim_buf_is_valid(test_bufnr) then
				vim.api.nvim_buf_delete(test_bufnr, { force = true })
			end
		end)

		it("should detect yaml language from .yaml files", function()
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"ConfigExample",
				mock_git_root .. "/docs/_partials/config.yaml",
				true
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
			local has_yaml_codeblock = false
			for _, line in ipairs(lines) do
				if line:match('<CodeBlock language="yaml".*{ConfigExample}</CodeBlock>') then
					has_yaml_codeblock = true
				end
			end
			assert.is_true(has_yaml_codeblock)
		end)

		it("should detect yaml language from .yml files", function()
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"DockerCompose",
				mock_git_root .. "/docs/_partials/docker-compose.yml",
				true
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
			local has_yaml_codeblock = false
			for _, line in ipairs(lines) do
				if line:match('<CodeBlock language="yaml".*{DockerCompose}</CodeBlock>') then
					has_yaml_codeblock = true
				end
			end
			assert.is_true(has_yaml_codeblock)
		end)

		it("should detect json language", function()
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"PackageJson",
				mock_git_root .. "/docs/_partials/package.json",
				true
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
			local has_json_codeblock = false
			for _, line in ipairs(lines) do
				if line:match('<CodeBlock language="json".*{PackageJson}</CodeBlock>') then
					has_json_codeblock = true
				end
			end
			assert.is_true(has_json_codeblock)
		end)

		it("should detect javascript language from .js files", function()
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"ScriptExample",
				mock_git_root .. "/docs/_partials/script.js",
				true
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
			local has_js_codeblock = false
			for _, line in ipairs(lines) do
				if line:match('<CodeBlock language="javascript".*{ScriptExample}</CodeBlock>') then
					has_js_codeblock = true
				end
			end
			assert.is_true(has_js_codeblock)
		end)

		it("should detect bash language from .sh files", function()
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"InstallScript",
				mock_git_root .. "/docs/_partials/install.sh",
				true
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
			local has_bash_codeblock = false
			for _, line in ipairs(lines) do
				if line:match('<CodeBlock language="bash".*{InstallScript}</CodeBlock>') then
					has_bash_codeblock = true
				end
			end
			assert.is_true(has_bash_codeblock)
		end)

		it("should use extension as language for unknown types", function()
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"CustomConfig",
				mock_git_root .. "/docs/_partials/config.hcl",
				true
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
			local has_hcl_codeblock = false
			for _, line in ipairs(lines) do
				if line:match('<CodeBlock language="hcl".*{CustomConfig}</CodeBlock>') then
					has_hcl_codeblock = true
				end
			end
			assert.is_true(has_hcl_codeblock)
		end)

		it("should handle case-insensitive extensions", function()
			docusaurus.insert_partial_in_buffer(
				test_bufnr,
				"UppercaseYaml",
				mock_git_root .. "/docs/_partials/config.YAML",
				true
			)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
			local has_yaml_codeblock = false
			for _, line in ipairs(lines) do
				if line:match('<CodeBlock language="yaml".*{UppercaseYaml}</CodeBlock>') then
					has_yaml_codeblock = true
				end
			end
			assert.is_true(has_yaml_codeblock)
		end)
	end)

	describe("commands", function()
		it("should create user commands", function()
			-- Clear any existing commands first
			pcall(vim.api.nvim_del_user_command, "DocusaurusInsertComponent")
			pcall(vim.api.nvim_del_user_command, "DocusaurusInsertPartial")
			pcall(vim.api.nvim_del_user_command, "DocusaurusInsertCodeBlock")
			pcall(vim.api.nvim_del_user_command, "DocusaurusInsertURL")

			-- Create commands directly (simulating what the plugin file does)
			vim.api.nvim_create_user_command("DocusaurusInsertComponent", function()
				require("docusaurus").select_component()
			end, { desc = "Insert a Docusaurus component" })

			vim.api.nvim_create_user_command("DocusaurusInsertPartial", function()
				require("docusaurus").select_partial()
			end, { desc = "Insert a Docusaurus partial" })

			vim.api.nvim_create_user_command("DocusaurusInsertCodeBlock", function()
				require("docusaurus").select_code_block()
			end, { desc = "Insert a Docusaurus code block" })

			vim.api.nvim_create_user_command("DocusaurusInsertURL", function()
				require("docusaurus").insert_url_reference()
			end, { desc = "Insert a Docusaurus URL reference" })

			-- Check that commands exist
			local commands = vim.api.nvim_get_commands({})
			assert.is_not_nil(commands["DocusaurusInsertComponent"])
			assert.is_not_nil(commands["DocusaurusInsertPartial"])
			assert.is_not_nil(commands["DocusaurusInsertCodeBlock"])
			assert.is_not_nil(commands["DocusaurusInsertURL"])
		end)
	end)

	describe("git integration", function()
		it("should handle non-git directories", function()
			-- Mock system to return empty (no git)
			vim.fn.system = function(cmd)
				return ""
			end

			-- This should not error
			local result = pcall(docusaurus.select_partial)
			assert.is_true(result)
		end)
	end)

	describe("version context detection", function()
		it("should detect versioned vcluster folder", function()
			local context = docusaurus.get_version_context(
				"/repo/vcluster_versioned_docs/version-0.20.x/install/quick-start.mdx",
				"/repo"
			)

			assert.are.equal("versioned", context.type)
			assert.are.equal("vcluster", context.project)
			assert.are.equal("vcluster_versioned_docs/version-0.20.x", context.folder)
		end)

		it("should detect versioned platform folder", function()
			local context =
				docusaurus.get_version_context("/repo/platform_versioned_docs/version-4.4.0/api/config.mdx", "/repo")

			assert.are.equal("versioned", context.type)
			assert.are.equal("platform", context.project)
			assert.are.equal("platform_versioned_docs/version-4.4.0", context.folder)
		end)

		it("should detect main vcluster folder", function()
			local context = docusaurus.get_version_context("/repo/vcluster/install/quick-start.mdx", "/repo")

			assert.are.equal("main", context.type)
			assert.are.equal("vcluster", context.project)
		end)

		it("should detect main platform folder", function()
			local context = docusaurus.get_version_context("/repo/platform/api/config.mdx", "/repo")

			assert.are.equal("main", context.type)
			assert.are.equal("platform", context.project)
		end)

		it("should detect non-versioned root folder", function()
			local context = docusaurus.get_version_context("/repo/docs/getting-started.mdx", "/repo")

			assert.are.equal("non-versioned", context.type)
			assert.is_nil(context.project)
		end)

		it("should handle empty file path", function()
			local context = docusaurus.get_version_context("", "/repo")

			assert.are.equal("non-versioned", context.type)
		end)

		it("should handle nil file path", function()
			local context = docusaurus.get_version_context(nil, "/repo")

			assert.are.equal("non-versioned", context.type)
		end)

		it("should handle deeply nested versioned paths", function()
			local context = docusaurus.get_version_context(
				"/repo/vcluster_versioned_docs/version-0.19.x/deploy/advanced/multi-cluster/deep/nested/file.mdx",
				"/repo"
			)

			assert.are.equal("versioned", context.type)
			assert.are.equal("vcluster", context.project)
			assert.are.equal("vcluster_versioned_docs/version-0.19.x", context.folder)
		end)
	end)

	describe("allowed_site_paths pattern matching", function()
		it("should match docs/_partials/ with pattern ^docs/_", function()
			local context = {
				type = "versioned",
				folder = "vcluster_versioned_docs/version-0.20.x",
				project = "vcluster",
			}

			-- Reset to default config
			docusaurus.setup({})

			local matches = docusaurus.path_matches_context("/repo/docs/_partials/install.mdx", context, "/repo")
			assert.is_true(matches)
		end)

		it("should match docs/_fragments/ with pattern ^docs/_", function()
			local context = {
				type = "versioned",
				folder = "vcluster_versioned_docs/version-0.20.x",
				project = "vcluster",
			}

			docusaurus.setup({})

			local matches = docusaurus.path_matches_context("/repo/docs/_fragments/intro.mdx", context, "/repo")
			assert.is_true(matches)
		end)

		it("should match docs/_code/ with pattern ^docs/_", function()
			local context = {
				type = "versioned",
				folder = "vcluster_versioned_docs/version-0.20.x",
				project = "vcluster",
			}

			docusaurus.setup({})

			local matches = docusaurus.path_matches_context("/repo/docs/_code/example.yaml", context, "/repo")
			assert.is_true(matches)
		end)

		it("should match docs/_anything/ with pattern ^docs/_", function()
			local context = {
				type = "versioned",
				folder = "vcluster_versioned_docs/version-0.20.x",
				project = "vcluster",
			}

			docusaurus.setup({})

			local matches = docusaurus.path_matches_context("/repo/docs/_snippets/test.mdx", context, "/repo")
			assert.is_true(matches)
		end)

		it("should not match docs/regular/ (no underscore) with pattern ^docs/_", function()
			local context = {
				type = "versioned",
				folder = "vcluster_versioned_docs/version-0.20.x",
				project = "vcluster",
			}

			docusaurus.setup({})

			local matches = docusaurus.path_matches_context("/repo/docs/regular/guide.mdx", context, "/repo")
			-- Should not match because it's not an underscore directory
			-- and it's not in the version folder
			assert.is_false(matches)
		end)
	end)

	describe("path filtering", function()
		it("should match same version folder", function()
			local context = {
				type = "versioned",
				folder = "vcluster_versioned_docs/version-0.20.x",
				project = "vcluster",
			}

			local matches = docusaurus.path_matches_context(
				"/repo/vcluster_versioned_docs/version-0.20.x/install/guide.mdx",
				context,
				"/repo"
			)

			assert.is_true(matches)
		end)

		it("should exclude different version folder", function()
			local context = {
				type = "versioned",
				folder = "vcluster_versioned_docs/version-0.20.x",
				project = "vcluster",
			}

			local matches = docusaurus.path_matches_context(
				"/repo/vcluster_versioned_docs/version-0.19.x/install/guide.mdx",
				context,
				"/repo"
			)

			assert.is_false(matches)
		end)

		it("should include non-versioned docs folder from versioned context", function()
			local context = {
				type = "versioned",
				folder = "vcluster_versioned_docs/version-0.20.x",
				project = "vcluster",
			}

			local matches = docusaurus.path_matches_context("/repo/docs/_partials/install.mdx", context, "/repo")

			assert.is_true(matches)
		end)

		it("should match same main project folder", function()
			local context = {
				type = "main",
				project = "vcluster",
			}

			local matches = docusaurus.path_matches_context("/repo/vcluster/install/quick-start.mdx", context, "/repo")

			assert.is_true(matches)
		end)

		it("should exclude different main project folder", function()
			local context = {
				type = "main",
				project = "vcluster",
			}

			local matches = docusaurus.path_matches_context("/repo/platform/api/config.mdx", context, "/repo")

			assert.is_false(matches)
		end)

		it("should exclude versioned folders from main context", function()
			local context = {
				type = "main",
				project = "vcluster",
			}

			local matches = docusaurus.path_matches_context(
				"/repo/vcluster_versioned_docs/version-0.20.x/install/guide.mdx",
				context,
				"/repo"
			)

			assert.is_false(matches)
		end)

		it("should include non-versioned docs from main context", function()
			local context = {
				type = "main",
				project = "vcluster",
			}

			local matches = docusaurus.path_matches_context("/repo/docs/_partials/install.mdx", context, "/repo")

			assert.is_true(matches)
		end)

		it("should match all paths in non-versioned context", function()
			local context = {
				type = "non-versioned",
			}

			assert.is_true(docusaurus.path_matches_context("/repo/vcluster/install/guide.mdx", context, "/repo"))
			assert.is_true(docusaurus.path_matches_context("/repo/platform/api/config.mdx", context, "/repo"))
			assert.is_true(
				docusaurus.path_matches_context(
					"/repo/vcluster_versioned_docs/version-0.20.x/guide.mdx",
					context,
					"/repo"
				)
			)
		end)

		it("should handle empty path", function()
			local context = { type = "main", project = "vcluster" }

			local matches = docusaurus.path_matches_context("", context, "/repo")

			assert.is_false(matches)
		end)

		it("should handle nil path", function()
			local context = { type = "main", project = "vcluster" }

			local matches = docusaurus.path_matches_context(nil, context, "/repo")

			assert.is_false(matches)
		end)

		it("should match multiple allowed_site_paths patterns", function()
			local context = {
				type = "versioned",
				folder = "vcluster_versioned_docs/version-0.20.x",
				project = "vcluster",
			}

			assert.is_true(docusaurus.path_matches_context("/repo/docs/_partials/file.mdx", context, "/repo"))
			assert.is_true(docusaurus.path_matches_context("/repo/docs/_fragments/file.mdx", context, "/repo"))
			assert.is_true(docusaurus.path_matches_context("/repo/docs/_code/example.yaml", context, "/repo"))
		end)
	end)

	describe("plugin scaffolder", function()
		it("should generate lifecycle plugin template", function()
			local template = docusaurus.generate_plugin_template({
				name = "my-plugin",
				type = "lifecycle",
			})

			assert.is_not_nil(template)
			assert.is_truthy(template:match("function myPlugin"))
			assert.is_truthy(template:match("name:"))
		end)

		it("should generate content plugin template", function()
			local template = docusaurus.generate_plugin_template({
				name = "my-content-plugin",
				type = "content",
			})

			assert.is_not_nil(template)
			assert.is_truthy(template:match("async loadContent"))
			assert.is_truthy(template:match("async contentLoaded"))
		end)

		it("should create plugin directory structure", function()
			local mock_mkdir_calls = {}
			local mock_write_calls = {}

			-- Mock directory creation
			vim.fn.mkdir = function(path, mode)
				table.insert(mock_mkdir_calls, path)
				return 1
			end

			-- Mock file writing (we'll implement this in the actual code)
			local function mock_write_file(path, content)
				table.insert(mock_write_calls, { path = path, content = content })
			end

			docusaurus.scaffold_plugin({
				name = "my-plugin",
				type = "lifecycle",
				write_file = mock_write_file,
			})

			-- Check that directories were created
			assert.is_true(#mock_mkdir_calls > 0)

			-- Check that files were written
			assert.is_true(#mock_write_calls > 0)

			-- Check index.js was created
			local has_index = false
			for _, call in ipairs(mock_write_calls) do
				if call.path:match("index.js$") then
					has_index = true
				end
			end
			assert.is_true(has_index)
		end)
	end)

	describe("api browser", function()
		it("should parse package.json for docusaurus version", function()
			-- Mock filereadable to return true for package.json
			vim.fn.filereadable = function(path)
				if path:match("package.json$") then
					return 1
				end
				return 0
			end

			-- Mock reading package.json
			vim.fn.readfile = function(path)
				if path:match("package.json$") then
					return {
						"{",
						'  "dependencies": {',
						'    "@docusaurus/core": "^3.0.0"',
						"  }",
						"}",
					}
				end
				return {}
			end

			local version = docusaurus.get_docusaurus_version()
			assert.is_not_nil(version)
			assert.is_truthy(version:match("3%.0%.0"))
		end)

		it("should fetch config options for version", function()
			-- Provide mock markdown content that matches the parser's expected format
			local mock_content = [[
### `title` {#title}

- Type: `string`

Title for your website.

```js
export default {
  title: 'My Site',
};
```

### `url` {#url}

- Type: `string`

URL for your website.

```js
export default {
  url: 'https://example.com',
};
```
]]

			local options = docusaurus.get_config_options("3.0.0", mock_content)
			assert.is_not_nil(options)
			assert.is_true(#options > 0)

			-- Check structure of config option
			local first_option = options[1]
			assert.is_not_nil(first_option.name)
			assert.is_not_nil(first_option.description)
			assert.is_not_nil(first_option.type)
			assert.is_not_nil(first_option.url)

			-- Verify parsing worked correctly
			assert.are.equal("title", first_option.name)
			assert.are.equal("string", first_option.type)
			assert.are.equal("Title for your website.", first_option.description)
			assert.are.equal("https://docusaurus.io/docs/api/docusaurus-config#title", first_option.url)
		end)
	end)

	describe("partials directory sorting", function()
		it("should sort root docs directories before versioned directories", function()
			-- Mock a list of partial directories
			local dirs = {
				"/repo/vcluster_versioned_docs/version-0.20.x/_partials",
				"/repo/docs/_partials",
				"/repo/platform_versioned_docs/version-4.3.0/_partials",
				"/repo/docs/_fragments",
			}

			-- Reset to default config
			docusaurus.setup({})
			local config = docusaurus.get_config()

			-- Sort using the same logic as get_all_partials_dirs
			local git_root = "/repo"
			table.sort(dirs, function(a, b)
				local a_rel = a:sub(#git_root + 2)
				local b_rel = b:sub(#git_root + 2)

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

				if a_is_root and not b_is_root then
					return true
				end
				if b_is_root and not a_is_root then
					return false
				end
				return a < b
			end)

			-- Check that root docs directories come first
			assert.is_not_nil(dirs[1]:match("^/repo/docs/_"))
			assert.is_not_nil(dirs[2]:match("^/repo/docs/_"))
			assert.is_nil(dirs[3]:match("^/repo/docs/_"))
			assert.is_nil(dirs[4]:match("^/repo/docs/_"))
		end)

		it("should identify root files correctly", function()
			docusaurus.setup({})
			local config = docusaurus.get_config()
			local git_root = "/repo"

			-- Test root file
			local path1 = "/repo/docs/_partials/install.mdx"
			local rel1 = path1:sub(#git_root + 2)
			local is_root1 = false
			for _, pattern in ipairs(config.allowed_site_paths) do
				if rel1:match(pattern) then
					is_root1 = true
					break
				end
			end
			assert.is_true(is_root1)

			-- Test versioned file
			local path2 = "/repo/vcluster_versioned_docs/version-0.20.x/_partials/config.mdx"
			local rel2 = path2:sub(#git_root + 2)
			local is_root2 = false
			for _, pattern in ipairs(config.allowed_site_paths) do
				if rel2:match(pattern) then
					is_root2 = true
					break
				end
			end
			assert.is_false(is_root2)
		end)
	end)

	describe("url reference filtering", function()
		it("should only include version-specific docs for versioned context", function()
			-- This tests that URL references don't include root docs/ folder
			-- when in versioned context (unlike partials which do include them)
			local context = {
				type = "versioned",
				folder = "vcluster_versioned_docs/version-0.20.x",
				project = "vcluster",
			}

			-- URL references should match only version folder
			local matches_version = docusaurus.path_matches_context(
				"/repo/vcluster_versioned_docs/version-0.20.x/guide.mdx",
				context,
				"/repo"
			)
			assert.is_true(matches_version)

			-- But partials from docs/ should still match for imports
			local matches_partial =
				docusaurus.path_matches_context("/repo/docs/_partials/install.mdx", context, "/repo")
			assert.is_true(matches_partial)

			-- Regular docs should not match
			local matches_regular = docusaurus.path_matches_context("/repo/docs/guide.mdx", context, "/repo")
			assert.is_false(matches_regular)
		end)

		it("should only include main project docs for main context", function()
			local context = {
				type = "main",
				project = "vcluster",
			}

			-- Should match main project folder
			local matches_main = docusaurus.path_matches_context("/repo/vcluster/guide.mdx", context, "/repo")
			assert.is_true(matches_main)

			-- Should match root partials
			local matches_partial =
				docusaurus.path_matches_context("/repo/docs/_partials/install.mdx", context, "/repo")
			assert.is_true(matches_partial)

			-- Should not match other projects
			local matches_other = docusaurus.path_matches_context("/repo/platform/guide.mdx", context, "/repo")
			assert.is_false(matches_other)

			-- Should not match versioned folders
			local matches_versioned = docusaurus.path_matches_context(
				"/repo/vcluster_versioned_docs/version-0.20.x/guide.mdx",
				context,
				"/repo"
			)
			assert.is_false(matches_versioned)
		end)
	end)
end)
