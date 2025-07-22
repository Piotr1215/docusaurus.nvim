if vim.g.loaded_docusaurus then
  return
end

vim.g.loaded_docusaurus = true

-- Create user commands
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