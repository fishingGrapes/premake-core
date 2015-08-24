--
-- Embed the Lua scripts into src/host/scripts.c as static data buffers.
-- I embed the actual scripts, rather than Lua bytecodes, because the
-- bytecodes are not portable to different architectures, which causes
-- issues in Mac OS X Universal builds.
--

	local function loadScript(fname)
		fname = path.getabsolute(fname)
		local f = io.open(fname)
		local s = assert(f:read("*a"))
		f:close()

		-- strip tabs
		s = s:gsub("[\t]", "")

		-- strip any CRs
		s = s:gsub("[\r]", "")

		-- strip out block comments
		s = s:gsub("[^\"']%-%-%[%[.-%]%]", "")
		s = s:gsub("[^\"']%-%-%[=%[.-%]=%]", "")
		s = s:gsub("[^\"']%-%-%[==%[.-%]==%]", "")

		-- strip out inline comments
		s = s:gsub("\n%-%-[^\n]*", "\n")

		-- escape backslashes
		s = s:gsub("\\", "\\\\")

		-- strip duplicate line feeds
		s = s:gsub("\n+", "\n")

		-- strip out leading comments
		s = s:gsub("^%-%-[^\n]*\n", "")

		-- escape line feeds
		s = s:gsub("\n", "\\n")

		-- escape double quote marks
		s = s:gsub("\"", "\\\"")

 		return s
	end


	local function appendScript(result, contents)
		-- break up large strings to fit in Visual Studio's string length limit
		local max = 4096
		local start = 1
		local len = contents:len()
		if len > 0 then
			while start <= len do
				local n = len - start
				if n > max then n = max end
				local finish = start + n

				-- make sure I don't cut an escape sequence
				while contents:sub(finish, finish) == "\\" do
					finish = finish - 1
				end

				local s = contents:sub(start, finish)
				table.insert(result, "\t\"" .. s .. iif(finish < len, '"', '",'))

				start = finish + 1
			end
		else
			table.insert(result, "\t\"\",")
		end

		table.insert(result, "")
	end



-- Prepare the file header

	local result = {}
	table.insert(result, "/* Premake's Lua scripts, as static data buffers for release mode builds */")
	table.insert(result, "/* DO NOT EDIT - this file is autogenerated - see BUILD.txt */")
	table.insert(result, "/* To regenerate this file, run: premake5 embed */")
	table.insert(result, "")
	table.insert(result, '#include "premake.h"')
	table.insert(result, "")


-- Find all of the _manifest.lua files within the project

	local mask = path.join(_MAIN_SCRIPT_DIR, "**/_manifest.lua")
	local manifests = os.matchfiles(mask)

-- Find all of the _user_modules.lua files within the project

	local userModuleFiles = {}
	userModuleFiles = table.join(userModuleFiles, os.matchfiles(path.join(_MAIN_SCRIPT_DIR, "**/_user_modules.lua")))
	userModuleFiles = table.join(userModuleFiles, os.matchfiles(path.join(_MAIN_SCRIPT_DIR, "_user_modules.lua")))

-- Generate an index of the script file names. Script names are stored
-- relative to the directory containing the manifest, i.e. the main
-- Xcode script, which is at $/modules/xcode/xcode.lua is stored as
-- "xcode/xcode.lua".

	table.insert(result, "const char* builtin_scripts_index[] = {")

	for mi = 1, #manifests do
		local manifestName = manifests[mi]
		local manifestDir = path.getdirectory(manifestName)
		local baseDir = path.getdirectory(manifestDir)

		local files = dofile(manifests[mi])
		for fi = 1, #files do
			local filename = path.join(manifestDir, files[fi])
			filename = path.getrelative(baseDir, filename)
			table.insert(result, '\t"' .. filename .. '",')
		end
	end

	table.insert(result, '\t"src/_premake_main.lua",')
	table.insert(result, '\t"src/_manifest.lua",')
	table.insert(result, '\t"src/_modules.lua",')
	table.insert(result, "\tNULL")
	table.insert(result, "};")
	table.insert(result, "")


-- Embed the actual script contents

	table.insert(result, "const char* builtin_scripts[] = {")

	for mi = 1, #manifests do
		local manifestName = manifests[mi]
		local manifestDir = path.getdirectory(manifestName)

		local files = dofile(manifests[mi])
		for fi = 1, #files do
			local filename = path.join(manifestDir, files[fi])

			local scr = loadScript(filename)
			appendScript(result, scr)
		end
	end

	appendScript(result, loadScript(path.join(_SCRIPT_DIR, "../src/_premake_main.lua")))
	appendScript(result, loadScript(path.join(_SCRIPT_DIR, "../src/_manifest.lua")))

-- Write the list of modules

	local modules = dofile("../src/_modules.lua")
	for _, userModules in ipairs(userModuleFiles) do
		modules = table.join(modules, dofile(userModules))
	end
	appendScript(result, "return {" .. table.implode(modules, "\\\"", "\\\"", ",\\n") .. "}")

	table.insert(result, "\tNULL")
	table.insert(result, "};")
	table.insert(result, "")


-- Write it all out. Check against the current contents of scripts.c first,
-- and only overwrite it if there are actual changes.

	result = table.concat(result, "\n")

	local scriptsFile = path.getabsolute(path.join(_SCRIPT_DIR, "../src/host/scripts.c"))

	local oldVersion
	local file = io.open(scriptsFile, "r")
	if file then
		oldVersion = file:read("*a")
		file:close()
	end

	if oldVersion ~= result then
		print("Writing scripts.c")
		file = io.open(scriptsFile, "w+b")
		file:write(result)
		file:close()
	end
