local SealedSecrets = {}

-- Default configuration
SealedSecrets.config = {
	cert_path = nil,
}

-- Debug-Funktion
local function debug_print(msg)
	if debug then
		print("[DEBUG] " .. msg)
	end
end

-- Setup function to configure the plugin
function SealedSecrets.setup(opts)
	SealedSecrets.config = vim.tbl_deep_extend("force", SealedSecrets.config, opts or {})

	if not SealedSecrets.config.cert_path then
		vim.notify("Kubeseal plugin: cert_path is not configured!", vim.log.levels.ERROR)
		return
	end

	-- Create the command that will be used
	vim.api.nvim_create_user_command("KubesealEncrypt", function(opts)
		if opts.range == 0 then
			-- Encrypt entire buffer when no range is selected
			SealedSecrets.encrypt_buffer()
		else
			-- Encrypt selection when range is selected
			SealedSecrets.encrypt_selection()
		end
	end, {
		range = true,
		desc = "Encrypt selected text or entire buffer using kubeseal",
	})

	-- keymap
	vim.keymap.set("v", "<leader>ks", function()
		SealedSecrets.encrypt_selection()
	end, {
		desc = "Encrypt selection with Kubeseal",
		silent = true,
	})
	vim.keymap.set("n", "<leader>ks", ":KubesealEncrypt<CR>", {
		desc = "Encrypt buffer with Kubeseal",
		silent = true,
	})
end

-- Function to encrypt the selected text
function SealedSecrets.encrypt_selection()
	-- 1. Retrieve the selected text
	vim.cmd('normal! "ay') -- Copy selected text to tab a
	local selected_text = vim.fn.getreg("a")
	--debug_print("Selected text:'" .. selected_text .. "'")

	-- Check for key-value pair
	local key, value = selected_text:match("([^:]+):%s*(.+)")
	local is_key_value = key ~= nil and value ~= nil
	local text_to_encrypt = is_key_value and value:gsub("^%s*(.-)%s*$", "%1") or selected_text

	-- 3. Encrypt the text
	local temp_input = vim.fn.tempname()
	local f = io.open(temp_input, "w")
	f:write(text_to_encrypt)
	f:close()

	local cmd = string.format(
		"cat %s | kubeseal --raw --scope cluster-wide --cert %s",
		temp_input,
		SealedSecrets.config.cert_path
	)

	local output = vim.fn.system(cmd)
	if vim.v.shell_error ~= 0 then
		vim.notify("Kubeseal encryption failed: " .. output, vim.log.levels.ERROR)
		return
	end

	--debug_print(output)
	if is_key_value then
		output = key .. ": " .. output
		output = output:gsub("$", "\n")
	end

	-- 4. Replace the text - DIRECT METHOD
	-- Delete the selection and insert the new text.
	vim.fn.setreg("b", output) -- Save encrypted text to register b
	vim.cmd('normal! gvd"bP') -- Delete selection (d) and add tab b (P)

	os.remove(temp_input)
	vim.notify("Text encrypted successfully!", vim.log.levels.INFO)
end

-- Function to encrypt the entire buffer
function SealedSecrets.encrypt_buffer()
	-- Get the current buffer content
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local text = table.concat(lines, "\n")

	-- Create a temporary file for the input
	local temp_input = vim.fn.tempname()
	local temp_output = vim.fn.tempname()
	local f = io.open(temp_input, "w")
	f:write(text)
	f:close()

	-- Build the kubeseal command for full buffer encryption
	local cmd = string.format(
		"kubeseal --scope cluster-wide --cert %s --format yaml <%s >%s",
		SealedSecrets.config.cert_path,
		temp_input,
		temp_output
	)

	-- Execute the command
	local result = vim.fn.system(cmd)

	-- Check for errors
	if vim.v.shell_error ~= 0 then
		vim.notify("Kubeseal encryption failed: " .. result, vim.log.levels.ERROR)
		return
	end

	-- Read the encrypted output
	local encrypted_content = {}
	for line in io.lines(temp_output) do
		table.insert(encrypted_content, line)
	end

	-- Replace the entire buffer content
	vim.api.nvim_buf_set_lines(0, 0, -1, false, encrypted_content)

	-- Clean up temporary files
	os.remove(temp_input)
	os.remove(temp_output)

	vim.notify("Buffer encrypted successfully!", vim.log.levels.INFO)
end

return SealedSecrets
