-- Streaming multipart/form-data parser built on resty.upload.
--
-- Text fields end up in `ctx.body` (repeated names become lists, like the
-- urlencoded parser); files are written chunk by chunk to temporary files
-- and exposed as
--
--   ctx.files[field] = { filename, content_type, size, path, field }
--
-- (a list when the field repeats). Temporary files are deleted when the
-- request ends unless the action keeps them with ctx:save_upload(file, dest).
--
-- Configuration (application config):
--   upload_dir   = "tmp/uploads"          -- temp dir (relative to the nginx prefix)
--   upload_root  = "/srv/app/storage"     -- the only tree save_upload writes into
--   upload = { max_file_size, max_files, max_fields, max_field_size,
--              max_total_size, chunk_size, timeout }
--   (`upload.dir` / `upload.root` are accepted as aliases)
local Crypto = require("crescent.security.crypto")

local Upload = {}

Upload.DEFAULTS = {
    max_file_size = 10 * 1024 * 1024,
    max_files = 10,
    max_fields = 100,
    max_field_size = 64 * 1024,
    max_total_size = 50 * 1024 * 1024,
    chunk_size = 8192,
    max_line_size = 4096,
}

local function prefix_path(path)
    if path:sub(1, 1) == "/" then return path end
    local prefix = ngx and ngx.config and ngx.config.prefix and ngx.config.prefix()
    if prefix and prefix ~= "" then return prefix:gsub("/$", "") .. "/" .. path end
    return path
end

function Upload.settings(config)
    config = config or {}
    local options = type(config.upload) == "table" and config.upload or {}
    local settings = {}
    for key, value in pairs(Upload.DEFAULTS) do settings[key] = value end
    for key, value in pairs(options) do settings[key] = value end
    settings.dir = prefix_path(options.dir or config.upload_dir or "tmp/uploads"):gsub("/+$", "")
    local root = options.root or config.upload_root
    if root then settings.root = prefix_path(root):gsub("/+$", "") end
    return settings
end

-- Filesystem helpers -------------------------------------------------------

local function exists(path)
    local ok = os.rename(path, path)
    return ok == true
end

local mkdir
do
    local ok, ffi = pcall(require, "ffi")
    if ok then
        pcall(ffi.cdef, "int mkdir(const char *path, unsigned int mode);")
        mkdir = function(path) return ffi.C.mkdir(path, 448) == 0 end -- 0700
    end
end

local function ensure_dir(path)
    if exists(path) then return true end
    if not mkdir then return false end
    local current = path:sub(1, 1) == "/" and "" or "."
    for segment in path:gmatch("[^/]+") do
        current = current .. "/" .. segment
        if not exists(current) then mkdir(current) end
    end
    return exists(path)
end

local function dirname(path)
    return path:match("^(.*)/[^/]*$") or "."
end

-- Header parsing -----------------------------------------------------------

local function trim(value)
    return (value:match("^%s*(.-)%s*$"))
end

local function percent_decode(value)
    return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

-- `form-data; name="field"; filename="a.txt"` -> "form-data", { name=..., filename=... }
function Upload.parse_disposition(value)
    local disposition, rest = value:match("^%s*([^;%s]+)%s*(.*)$")
    if not disposition then return nil end
    local params = {}
    local position = 1
    while position <= #rest do
        local key, after = rest:match("^%s*;%s*([^=%s;]+)%s*=%s*()", position)
        if not key then
            if rest:match("^[%s;]*$", position) then break end
            return nil
        end
        local param
        if rest:sub(after, after) == '"' then
            local buffer, index = {}, after + 1
            while true do
                local char = rest:sub(index, index)
                if char == "" then return nil end
                local escaped = char == "\\" and rest:sub(index + 1, index + 1)
                -- Only \" and \\ are escapes: browsers send Windows paths raw.
                if escaped == '"' or escaped == "\\" then
                    buffer[#buffer + 1] = escaped
                    index = index + 2
                elseif char == '"' then
                    break
                else
                    buffer[#buffer + 1] = char
                    index = index + 1
                end
            end
            param, position = table.concat(buffer), index + 1
        else
            local token, next_position = rest:match("^([^;]*)()", after)
            param, position = trim(token), next_position
        end
        params[key:lower()] = param
    end
    if not params.filename and params["filename*"] then
        local encoded = params["filename*"]:match("^[%w%-]*'[^']*'(.*)$")
        if encoded then params.filename = percent_decode(encoded) end
    end
    return disposition:lower(), params
end

-- Basename only, no control characters, no leading dots, at most 255 bytes.
function Upload.sanitize_filename(name)
    name = tostring(name or ""):gsub("[%z\1-\31\127]", "")
    name = name:match("([^/\\]*)$")
    name = trim(name):gsub("^%.+", "")
    if #name > 255 then name = name:sub(-255) end
    if name == "" then name = "upload" end
    return name
end

-- Parser -------------------------------------------------------------------

local function add_value(target, key, value)
    local current = target[key]
    if current == nil then
        target[key] = value
    elseif type(current) == "table" and current.path == nil and current[1] ~= nil then
        current[#current + 1] = value
    else
        target[key] = { current, value }
    end
end

local function failure(status, message, code)
    return { status = status, message = message, code = code }
end

local function remove_files(paths)
    for _, path in ipairs(paths) do os.remove(path) end
end

-- `reader` follows resty.upload's interface: reader:read() returns
-- typ ("header" | "body" | "part_end" | "eof"), value, err.
-- Returns body, files or nil, { status, message, code }.
function Upload.parse(reader, settings)
    settings = settings or Upload.settings()
    local body, files = {}, {}
    local created = {}
    local field_count, file_count, total = 0, 0, 0
    local part

    local function fail(status, message, code)
        if part and part.handle then part.handle:close() end
        remove_files(created)
        return nil, failure(status, message, code)
    end

    local function begin_body()
        part.ready = true
        if part.disposition ~= "form-data" or not part.name or part.name == "" then
            return fail(400, "malformed multipart body", "malformed_multipart")
        end
        if part.filename == nil then
            field_count = field_count + 1
            if field_count > settings.max_fields then
                return fail(413, "too many form fields", "too_many_fields")
            end
            part.chunks = {}
            return true
        end
        file_count = file_count + 1
        if file_count > settings.max_files then
            return fail(413, "too many files", "too_many_files")
        end
        if not ensure_dir(settings.dir) then
            return fail(500, "upload directory is not writable", "upload_unavailable")
        end
        part.path = settings.dir .. "/crescent-" .. Crypto.random_hex(16) .. ".upload"
        local handle, open_error = io.open(part.path, "wb")
        if not handle then
            return fail(500, "unable to store upload: " .. tostring(open_error), "upload_unavailable")
        end
        created[#created + 1] = part.path
        part.handle = handle
        return true
    end

    local function write(chunk)
        total = total + #chunk
        if total > settings.max_total_size then
            return fail(413, "request body too large", "upload_too_large")
        end
        part.size = part.size + #chunk
        if part.handle then
            if part.size > settings.max_file_size then
                return fail(413, "file too large", "upload_too_large")
            end
            local ok, write_error = part.handle:write(chunk)
            if not ok then return fail(500, "unable to store upload: " .. tostring(write_error), "upload_unavailable") end
        else
            if part.size > settings.max_field_size then
                return fail(413, "form field too large", "upload_too_large")
            end
            part.chunks[#part.chunks + 1] = chunk
        end
        return true
    end

    local function finish()
        if part.handle then
            part.handle:close()
            part.handle = nil
            -- Browsers send an empty part with filename="" for an empty file input.
            if part.filename == "" and part.size == 0 then
                os.remove(part.path)
                file_count = file_count - 1
            else
                add_value(files, part.name, {
                    field = part.name,
                    filename = Upload.sanitize_filename(part.filename),
                    content_type = part.content_type or "application/octet-stream",
                    size = part.size,
                    path = part.path,
                })
            end
        else
            add_value(body, part.name, table.concat(part.chunks))
        end
        part = nil
        return true
    end

    while true do
        local typ, value, read_error = reader:read()
        if not typ then
            return fail(400, "malformed multipart body: " .. tostring(read_error), "malformed_multipart")
        end
        local ok, err = true, nil
        if typ == "header" then
            part = part or { size = 0 }
            if part.ready or type(value) ~= "table" then
                return fail(400, "malformed multipart body", "malformed_multipart")
            end
            local name = tostring(value[1] or ""):lower()
            if name == "content-disposition" then
                local disposition, params = Upload.parse_disposition(tostring(value[2] or ""))
                if not disposition then return fail(400, "malformed multipart body", "malformed_multipart") end
                part.disposition, part.name, part.filename = disposition, params.name, params.filename
            elseif name == "content-type" then
                part.content_type = trim(tostring(value[2] or ""))
            end
        elseif typ == "body" then
            part = part or { size = 0 }
            if not part.ready then ok, err = begin_body() end
            if ok then ok, err = write(value or "") end
        elseif typ == "part_end" then
            if not part then return fail(400, "malformed multipart body", "malformed_multipart") end
            if not part.ready then ok, err = begin_body() end
            if ok then ok, err = finish() end
        elseif typ == "eof" then
            if part then return fail(400, "malformed multipart body", "malformed_multipart") end
            break
        else
            return fail(400, "malformed multipart body", "malformed_multipart")
        end
        if not ok then return nil, err end
    end
    return body, files
end

local function each_file(files, callback)
    for _, entry in pairs(files or {}) do
        if type(entry) == "table" and entry.path then
            callback(entry)
        elseif type(entry) == "table" then
            for _, file in ipairs(entry) do callback(file) end
        end
    end
end

-- Deletes temporary files that were not moved with save().
function Upload.cleanup(files)
    each_file(files, function(file)
        if not file.saved and file.path then os.remove(file.path) end
    end)
end

local function copy_file(source, destination)
    local input = io.open(source, "rb")
    if not input then return false end
    local output = io.open(destination, "wb")
    if not output then input:close() return false end
    while true do
        local chunk = input:read(65536)
        if not chunk then break end
        output:write(chunk)
    end
    input:close()
    output:close()
    os.remove(source)
    return true
end

-- Moves an uploaded file to `destination` (relative to the upload root, or an
-- absolute path inside it). Refuses traversal and anything outside the root;
-- refuses to overwrite unless options.overwrite. Returns the final path or
-- nil, message.
function Upload.save(file, destination, config, options)
    options = options or {}
    local settings = Upload.settings(config)
    local root = settings.root
    if not root then error("save_upload requires config.upload_root", 2) end
    if type(file) ~= "table" or type(file.path) ~= "string" or file.saved then
        return nil, "not a pending upload"
    end
    if type(destination) ~= "string" or destination == "" or destination:find("[%z\r\n]") then
        return nil, "invalid destination"
    end
    local path = destination:sub(1, 1) == "/" and destination or root .. "/" .. destination
    for segment in path:gmatch("[^/]+") do
        if segment == ".." or segment == "." then return nil, "invalid destination" end
    end
    path = path:gsub("/+", "/")
    if path:sub(1, #root + 1) ~= root .. "/" or path:sub(-1) == "/" then
        return nil, "destination outside the upload root"
    end
    if exists(path) and not options.overwrite then return nil, "destination already exists" end
    if not ensure_dir(dirname(path)) then return nil, "unable to create destination directory" end
    if not os.rename(file.path, path) and not copy_file(file.path, path) then
        return nil, "unable to move upload"
    end
    file.path = path
    file.saved = true
    return path
end

function Upload.is_multipart(content_type)
    return type(content_type) == "string" and content_type:lower():match("^%s*multipart/form%-data") ~= nil
end

-- Parses the request body of the current nginx request into `request`.
-- `ngx_api.upload_reader(settings)` may supply a reader (tests).
function Upload.read_request(ngx_api, request, config)
    local settings = Upload.settings(config)
    local reader, reader_error
    if ngx_api.upload_reader then
        reader, reader_error = ngx_api.upload_reader(settings)
    else
        local resty_upload = require("resty.upload")
        reader, reader_error = resty_upload:new(settings.chunk_size, settings.max_line_size)
        if reader and settings.timeout then reader:set_timeout(settings.timeout) end
    end
    local body, files_or_error
    if reader then
        body, files_or_error = Upload.parse(reader, settings)
    else
        files_or_error = failure(400, "malformed multipart body: " .. tostring(reader_error), "malformed_multipart")
    end
    if not body then
        request.body_error = files_or_error.message
        if files_or_error.status == 413 then
            request.body_error_message = files_or_error.message
        elseif files_or_error.status >= 500 then
            request.body_error_message = "unable to process upload"
        end
        request.body_error_code = files_or_error.code
        request.body_error_status = files_or_error.status
        return request
    end
    request.body = body
    request.files = files_or_error
    return request
end

return Upload
