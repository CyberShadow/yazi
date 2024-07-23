local WRONG_PWD = "Cannot open encrypted archive. Wrong password?"

local M = {}

function M:setup()
	ps.sub_remote("extract", function(args)
		for _, arg in ipairs(args) do
			ya.manager_emit("plugin", { self._id, args = ya.quote(arg, true) })
		end
	end)
end

function M.entry(_, args)
	if not args[1] then
		error("No URL provided")
	end

	local url, pwd = Url(args[1]), ""
	while true do
		if not M.try_with(url, pwd) then
			break
		end

		local value, event = ya.input {
			title = string.format('Password for "%s":', url:name()),
			position = { "center", w = 50 },
		}
		if event == 1 then
			pwd = value
		else
			break
		end
	end
end

function M.try_with(url, pwd)
	local actual, assumed = M.output_url(url)
	if not actual then
		error("Cannot determine the output directory " .. url)
	end

	local child, code = require("archive"):spawn_7z { "x", "-aou", "-p" .. pwd, "-o" .. tostring(actual), tostring(url) }
	if not child then
		error("Spawn `7z` and `7zz` both commands failed, error code: " .. code)
	end

	local output, err = child:wait_with_output()
	if not output then
		error("7zip failed to output, error code " .. tostring(err))
	elseif output.status.code == 2 and output.stderr:find(WRONG_PWD, 1, true) then
		return true -- Needs retry
	elseif output.status.code ~= 0 then
		error("7zip exited with error code " .. tostring(output.status.code))
	end

	if assumed then -- Needs a move
		local unique = fs.unique_name(assumed)
		if unique then
			os.rename(tostring(actual:join(assumed:name())), tostring(unique))
			os.remove(tostring(actual))
		end
	end
end

function M.output_url(url)
	local parent = url:parent()
	if not parent then
		return
	end

	local archive = require("archive")
	local child = archive:spawn_7z { "l", "-ba", "-x!*/*", tostring(url) }
	if not child then
		return
	end

	local lines = {}
	repeat
		local next, event = child:read_line()
		if event == 0 or event == 1 then
			lines[#lines + 1] = next
		else
			break
		end
	until #lines >= 2
	child:start_kill()

	if #lines ~= 1 then
		local name = M.trim_ext(url:name())
		return fs.unique_name(parent:join(name))
	end

	local attr, _, name = lines[1]:match(archive.PAT_MATCH)
	if name and attr:sub(1, 1) == "D" then
		local assumed = parent:join(name)
		if fs.cha(assumed) then
			local tmp = string.format(".extract_%s", ya.time())
			return fs.unique_name(parent:join(tmp)), assumed
		end
	end

	return parent
end

function M.trim_ext(name)
	-- stylua: ignore
	local exts = { ["7z"] = true, apk = true, bz2 = true, bzip2 = true, exe = true, gz = true, gzip = true, iso = true, jar = true, rar = true, tar = true, tgz = true, xz = true, zip = true, zst = true }

	while true do
		local s = name:gsub("%.([a-zA-Z0-9]+)$", function(s) return (exts[s] or exts[s:lower()]) and "" end)
		if s == name or s == "" then
			break
		else
			name = s
		end
	end
	return name
end

return M
