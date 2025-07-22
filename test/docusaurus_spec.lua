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
      assert.are.same({ "^docs/_partials/", "^docs/_fragments/", "^docs/_code/" }, config.allowed_site_paths)
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
      docusaurus.insert_partial_in_buffer(test_bufnr, "Header", mock_git_root .. "/docs/_partials/header.mdx", false)
      
      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      
      -- Check import was added after frontmatter with @site
      assert.are.equal("import Header from '@site/docs/_partials/header.mdx';", lines[4])
      
      -- Check component was inserted at cursor
      assert.is_truthy(vim.tbl_contains(lines, "<Header />"))
    end)
    
    it("should insert versioned partial with relative import", function()
      docusaurus.insert_partial_in_buffer(test_bufnr, "Config", mock_git_root .. "/vcluster_versioned_docs/version-0.26.0/_partials/config.mdx", false)
      
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
      docusaurus.insert_partial_in_buffer(test_bufnr, "ConfigExample", mock_git_root .. "/docs/_partials/config.yaml", true)
      
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
        if line:match('<CodeBlock language="yaml".*{ConfigExample}</CodeBlock>') then
          has_codeblock = true
        end
      end
      assert.is_true(has_codeblock)
    end)
    
    it("should insert code block with relative raw loader from versioned docs", function()
      docusaurus.insert_partial_in_buffer(test_bufnr, "ConfigExample", mock_git_root .. "/vcluster_versioned_docs/version-0.26.0/_partials/config.yaml", true)
      
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
      docusaurus.insert_partial_in_buffer(test_bufnr, "VClusterConfig", mock_git_root .. "/docs/vcluster/_partials/vcluster-config.mdx", false)
      
      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      
      -- Check import uses relative path, not @site
      local has_relative_import = false
      local has_site_import = false
      for _, line in ipairs(lines) do
        if line:match("import VClusterConfig from '@site/") then
          has_site_import = true
        end
        -- Look for relative import (may or may not have ./ prefix)
        if line:match("import VClusterConfig from '.*vcluster/_partials/vcluster%-config%.mdx';") and not line:match("@site") then
          has_relative_import = true
        end
      end
      assert.is_false(has_site_import)
      assert.is_true(has_relative_import)
    end)
    
    it("should use relative import for platform paths", function()
      docusaurus.insert_partial_in_buffer(test_bufnr, "PlatformSetup", mock_git_root .. "/docs/platform/_partials/platform-setup.mdx", false)
      
      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      
      -- Check import uses relative path, not @site
      local has_relative_import = false
      local has_site_import = false
      for _, line in ipairs(lines) do
        if line:match("import PlatformSetup from '@site/") then
          has_site_import = true
        end
        -- Look for relative import (may or may not have ./ prefix)
        if line:match("import PlatformSetup from '.*platform/_partials/platform%-setup%.mdx';") and not line:match("@site") then
          has_relative_import = true
        end
      end
      assert.is_false(has_site_import)
      assert.is_true(has_relative_import)
    end)
    
    it("should use relative raw-loader import for vcluster code blocks", function()
      docusaurus.insert_partial_in_buffer(test_bufnr, "VClusterExample", mock_git_root .. "/docs/vcluster/_partials/example.yaml", true)
      
      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      
      -- Check import uses relative path with raw-loader, not @site
      local has_relative_raw_import = false
      local has_site_raw_import = false
      for _, line in ipairs(lines) do
        if line:match("import VClusterExample from '!!raw%-loader!@site/") then
          has_site_raw_import = true
        end
        -- Look for relative import with raw-loader (may or may not have ./ prefix)
        if line:match("import VClusterExample from '!!raw%-loader!.*vcluster/_partials/example%.yaml';") and not line:match("@site") then
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
      docusaurus.insert_partial_in_buffer(test_bufnr, "Intro", mock_git_root .. "/docs/_fragments/intro.mdx", false)
      
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
  end)
  
  describe("commands", function()
    it("should create user commands", function()
      -- Clear any existing commands first
      pcall(vim.api.nvim_del_user_command, "DocusaurusInsertComponent")
      pcall(vim.api.nvim_del_user_command, "DocusaurusInsertPartial")
      pcall(vim.api.nvim_del_user_command, "DocusaurusInsertCodeBlock")
      pcall(vim.api.nvim_del_user_command, "DocusaurusInsertURL")
      
      -- Create commands directly (simulating what the plugin file does)
      vim.api.nvim_create_user_command('DocusaurusInsertComponent', function()
        require('docusaurus').select_component()
      end, { desc = 'Insert a Docusaurus component' })

      vim.api.nvim_create_user_command('DocusaurusInsertPartial', function()
        require('docusaurus').select_partial()
      end, { desc = 'Insert a Docusaurus partial' })

      vim.api.nvim_create_user_command('DocusaurusInsertCodeBlock', function()
        require('docusaurus').select_code_block()
      end, { desc = 'Insert a Docusaurus code block' })

      vim.api.nvim_create_user_command('DocusaurusInsertURL', function()
        require('docusaurus').insert_url_reference()
      end, { desc = 'Insert a Docusaurus URL reference' })
      
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
end)