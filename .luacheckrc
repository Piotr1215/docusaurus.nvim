globals = {
  "vim",
  "describe",
  "it",
  "before_each",
  "after_each",
  "pending",
}

read_globals = {
  "vim",
}

exclude_files = {
  "/tmp/",
}

-- Allow unused variables in certain patterns
ignore = {
  "212",  -- Unused argument
  "213",  -- Unused loop variable
  "611",  -- Line contains only whitespace
  "614",  -- Trailing whitespace in comment
  "631",  -- Line is too long
}

-- For test files, allow modifying vim functions
files["test/*.lua"] = {
  std = "lua51+busted",
  globals = { "vim" },
  read_globals = { "assert", "describe", "it", "before_each", "after_each" },
}

-- For main plugin files
files["lua/**/*.lua"] = {
  ignore = { "122" }, -- Setting read-only field (vim.bo is valid)
}