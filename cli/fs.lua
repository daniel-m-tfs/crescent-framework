-- Small filesystem helpers shared by the CLI commands. Works on plain Lua 5.1+
-- and under `resty`. Every path that reaches a shell is single-quoted; callers
-- still validate user-supplied names before building paths.
local fs = {}

function fs.shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- os.execute returns `true|nil, "exit", code` on Lua 5.2+ (and LuaJIT built
-- with 5.2 compat) but a bare status code on plain Lua 5.1.
local function succeeded(first, _, code)
    if type(first) == "number" then return first == 0 end
    return first == true and (code == nil or code == 0)
end

function fs.execute(command)
    return succeeded(os.execute(command))
end

function fs.exists(path)
    local file = io.open(path, "r")
    if file then file:close() return true end
    return fs.execute("test -e " .. fs.shell_quote(path))
end

function fs.is_dir(path)
    return fs.execute("test -d " .. fs.shell_quote(path))
end

function fs.mkdir_p(path)
    if fs.is_dir(path) then return true end
    if fs.execute("mkdir -p " .. fs.shell_quote(path)) then return true end
    return nil, "unable to create directory " .. path
end

function fs.dirname(path)
    return path:match("^(.*)/[^/]*$") or "."
end

function fs.join(...)
    local parts = {}
    for _, part in ipairs({ ... }) do
        if part ~= "" and part ~= "." then parts[#parts + 1] = (tostring(part):gsub("/+$", "")) end
    end
    return table.concat(parts, "/")
end

function fs.read(path)
    local file, err = io.open(path, "rb")
    if not file then return nil, err end
    local content = file:read("*a")
    file:close()
    return content
end

-- Writes a new file; refuses to replace an existing one.
function fs.write_new(path, content)
    if fs.exists(path) then return nil, "file already exists: " .. path end
    local ok, err = fs.mkdir_p(fs.dirname(path))
    if not ok then return nil, err end
    local file, open_error = io.open(path, "wb")
    if not file then return nil, open_error end
    file:write(content)
    file:close()
    return true
end

-- Lists regular files below `root`, as paths relative to it, sorted.
function fs.list_files(root)
    local files = {}
    local handle = io.popen("cd " .. fs.shell_quote(root) .. " && find . -type f 2>/dev/null")
    if not handle then return files end
    for line in handle:lines() do
        local relative = line:gsub("^%./", "")
        if not relative:match("%.DS_Store$") then files[#files + 1] = relative end
    end
    handle:close()
    table.sort(files)
    return files
end

function fs.chmod_executable(path)
    return fs.execute("chmod 755 " .. fs.shell_quote(path))
end

function fs.cwd()
    local pwd = os.getenv("PWD")
    if pwd and pwd ~= "" then return pwd end
    local handle = io.popen("pwd")
    if not handle then return "." end
    local value = (handle:read("*l") or "."):gsub("%s+$", "")
    handle:close()
    return value
end

return fs
