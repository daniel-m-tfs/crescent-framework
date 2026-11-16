package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")
local Upload = require("crescent.upload")

local base = os.tmpname()
os.remove(base)
local TEMP_DIR = base .. "-uploads"
local ROOT = base .. "-storage"

local function list_dir(path)
    local handle = io.popen("ls -A '" .. path .. "' 2>/dev/null")
    local names = {}
    for name in handle:lines() do names[#names + 1] = name end
    handle:close()
    return names
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

-- Fake resty.upload reader. Each part: { name=, filename=, content_type=, chunks = {...} }
-- or { headers = {{k, v}}, chunks = {} } for raw headers.
local function fake_reader(parts, options)
    options = options or {}
    local events = {}
    for _, part in ipairs(parts) do
        local headers = part.headers
        if not headers then
            local disposition = 'form-data; name="' .. part.name .. '"'
            if part.filename then disposition = disposition .. '; filename="' .. part.filename .. '"' end
            headers = { { "Content-Disposition", disposition } }
            if part.content_type then headers[#headers + 1] = { "Content-Type", part.content_type } end
        end
        for _, header in ipairs(headers) do
            events[#events + 1] = { "header", { header[1], header[2], header[1] .. ": " .. header[2] } }
        end
        for _, chunk in ipairs(part.chunks or {}) do events[#events + 1] = { "body", chunk } end
        if not part.unterminated then events[#events + 1] = { "part_end" } end
    end
    if options.error then
        events[#events + 1] = { nil, nil, options.error }
    else
        events[#events + 1] = { "eof" }
    end
    local index = 0
    return {
        read = function()
            index = index + 1
            local event = events[index]
            assert(event, "read past eof")
            return event[1], event[2], event[3]
        end,
    }
end

local function settings(overrides)
    local config = { upload_dir = TEMP_DIR, upload = overrides or {} }
    return Upload.settings(config)
end

local function parse(parts, overrides, reader_options)
    return Upload.parse(fake_reader(parts, reader_options), settings(overrides))
end

local suite = {
    fields_and_files = function()
        local body, files = parse({
            { name = "title", chunks = { "Hello ", "world" } },
            { name = "tag", chunks = { "a" } },
            { name = "tag", chunks = { "b" } },
            { name = "tag", chunks = { "c" } },
            { name = "avatar", filename = "../../etc/passwd", content_type = "image/png", chunks = { "PNG", "DATA" } },
            { name = "docs", filename = "C:\\Users\\x\\report.pdf", chunks = { "pdf" } },
            { name = "docs", filename = ".hidden.txt", chunks = { "" } },
            { name = "empty_input", filename = "", content_type = "application/octet-stream", chunks = {} },
        })
        tests.assertNotNil(body)
        tests.assertEquals(body.title, "Hello world")
        tests.assertTableEquals(body.tag, { "a", "b", "c" })

        local avatar = files.avatar
        tests.assertEquals(avatar.filename, "passwd")
        tests.assertEquals(avatar.content_type, "image/png")
        tests.assertEquals(avatar.size, 7)
        tests.assertEquals(avatar.field, "avatar")
        tests.assertEquals(read_file(avatar.path), "PNGDATA")
        tests.assertEquals(avatar.path:sub(1, #TEMP_DIR + 1), TEMP_DIR .. "/")

        tests.assertEquals(#files.docs, 2)
        tests.assertEquals(files.docs[1].filename, "report.pdf")
        tests.assertEquals(files.docs[1].content_type, "application/octet-stream")
        tests.assertEquals(files.docs[2].filename, "hidden.txt")
        tests.assertEquals(files.docs[2].size, 0)
        tests.assertNil(files.empty_input, "an empty file input is not a file")
        tests.assertEquals(#list_dir(TEMP_DIR), 3)

        Upload.cleanup(files)
        tests.assertEquals(#list_dir(TEMP_DIR), 0, "cleanup removes temp files")
    end,

    sanitize_filename = function()
        tests.assertEquals(Upload.sanitize_filename("a/b/../c.txt"), "c.txt")
        tests.assertEquals(Upload.sanitize_filename("..\\..\\x.exe"), "x.exe")
        tests.assertEquals(Upload.sanitize_filename("bad\0na\nme.txt"), "badname.txt")
        tests.assertEquals(Upload.sanitize_filename(".."), "upload")
        tests.assertEquals(Upload.sanitize_filename("dir/"), "upload")
        tests.assertEquals(#Upload.sanitize_filename(string.rep("a", 300) .. ".txt"), 255)
    end,

    parse_disposition = function()
        local kind, params = Upload.parse_disposition('form-data; name="a;b"; filename="say \\"hi\\".txt"')
        tests.assertEquals(kind, "form-data")
        tests.assertEquals(params.name, "a;b")
        tests.assertEquals(params.filename, 'say "hi".txt')
        local _, star = Upload.parse_disposition("form-data; name=file; filename*=UTF-8''na%C3%AFve.txt")
        tests.assertEquals(star.name, "file")
        tests.assertEquals(star.filename, "na\195\175ve.txt")
        tests.assertNil(Upload.parse_disposition('form-data; name="unterminated'))
        tests.assertNil(Upload.parse_disposition("form-data; garbage"))
    end,

    limits = function()
        local function expect(result, status, code, err)
            tests.assertNil(result)
            tests.assertEquals(err.status, status)
            tests.assertEquals(err.code, code)
            tests.assertEquals(#list_dir(TEMP_DIR), 0, "temp files are removed on failure")
        end
        local big = { name = "f", filename = "big.bin", chunks = { string.rep("x", 600), string.rep("x", 600) } }
        local ok, err = parse({ { name = "f", filename = "a", chunks = { "1" } }, big }, { max_file_size = 1000 })
        expect(ok, 413, "upload_too_large", err)

        local files = {}
        for i = 1, 3 do files[i] = { name = "f" .. i, filename = "x", chunks = { "1" } } end
        ok, err = parse(files, { max_files = 2 })
        expect(ok, 413, "too_many_files", err)

        local fields = {}
        for i = 1, 4 do fields[i] = { name = "k" .. i, chunks = { "v" } } end
        ok, err = parse(fields, { max_fields = 3 })
        expect(ok, 413, "too_many_fields", err)

        ok, err = parse({ { name = "k", chunks = { string.rep("v", 20) } } }, { max_field_size = 10 })
        expect(ok, 413, "upload_too_large", err)

        ok, err = parse({
            { name = "a", filename = "a", chunks = { string.rep("x", 60) } },
            { name = "b", filename = "b", chunks = { string.rep("x", 60) } },
        }, { max_total_size = 100 })
        expect(ok, 413, "upload_too_large", err)
    end,

    malformed = function()
        local function expect(result, err)
            tests.assertNil(result)
            tests.assertEquals(err.status, 400)
            tests.assertEquals(err.code, "malformed_multipart")
            tests.assertEquals(#list_dir(TEMP_DIR), 0)
        end
        local ok, err = parse({ { headers = { { "Content-Disposition", "form-data" } }, chunks = { "x" } } })
        expect(ok, err)
        ok, err = parse({ { headers = { { "Content-Disposition", 'attachment; name="x"' } }, chunks = { "x" } } })
        expect(ok, err)
        ok, err = parse({ { headers = { { "Content-Type", "text/plain" } }, chunks = { "x" } } })
        expect(ok, err)
        ok, err = parse({ { name = "f", filename = "a", chunks = { "partial" } } }, nil, { error = "socket closed" })
        expect(ok, err)
        tests.assertContains(err.message, "socket closed")
        ok, err = parse({ { name = "f", filename = "a", chunks = { "x" }, unterminated = true } })
        expect(ok, err)
    end,

    request_integration = function()
        local saved_path, temp_path
        local app = Crescent.new({
            logger = function() end, secret_key = string.rep("k", 32),
            upload_dir = TEMP_DIR, upload_root = ROOT, upload = { max_file_size = 100 },
        })
        app:post("/upload", function(ctx)
            temp_path = ctx.files.photo.path
            local keep = ctx.files.keep
            saved_path = assert(ctx:save_upload(keep, "avatars/" .. keep.filename))
            local outside, outside_error = ctx:save_upload(ctx.files.photo, "../escape.txt")
            tests.assertNil(outside)
            tests.assertEquals(outside_error, "invalid destination")
            tests.assertNil(ctx:save_upload(ctx.files.photo, "/etc/escape.txt"))
            tests.assertNil(ctx:save_upload(ctx.files.photo, "avatars/" .. keep.filename), "no overwrite")
            return ctx:json(200, { title = ctx.body.title, size = ctx.files.photo.size })
        end)

        local read_body_called = false
        local function fake_ngx(parts)
            local output = {}
            return {
                req = {
                    get_headers = function() return { ["Content-Type"] = "multipart/form-data; boundary=x" } end,
                    get_method = function() return "POST" end,
                    get_uri_args = function() return {} end,
                    read_body = function() read_body_called = true end,
                    get_body_data = function() read_body_called = true end,
                },
                var = { uri = "/upload" },
                header = {},
                print = function(value) output[#output + 1] = value end,
                upload_reader = function(upload_settings)
                    tests.assertEquals(upload_settings.max_file_size, 100)
                    return fake_reader(parts)
                end,
            }, output
        end

        local api, output = fake_ngx({
            { name = "title", chunks = { "Trip" } },
            { name = "photo", filename = "beach.jpg", chunks = { "JPEGDATA" } },
            { name = "keep", filename = "me.png", chunks = { "PNG" } },
        })
        app:run(api)
        tests.assertEquals(api.status, 200, table.concat(output))
        tests.assertContains(output[1], '"title":"Trip"')
        tests.assertContains(output[1], '"size":8')
        tests.assertFalse(read_body_called, "multipart bodies are streamed, not read")
        tests.assertNil(read_file(temp_path), "unsaved uploads are deleted after the request")
        tests.assertEquals(saved_path, ROOT .. "/avatars/me.png")
        tests.assertEquals(read_file(saved_path), "PNG", "saved uploads survive the request")
        tests.assertEquals(#list_dir(TEMP_DIR), 0)

        local too_big = fake_ngx({ { name = "photo", filename = "x", chunks = { string.rep("x", 200) } } })
        app:run(too_big)
        tests.assertEquals(too_big.status, 413)
        tests.assertEquals(#list_dir(TEMP_DIR), 0)

        os.remove(saved_path)
        os.remove(ROOT .. "/avatars")
        os.remove(ROOT)
    end,

    save_requires_root = function()
        local _, files = parse({ { name = "f", filename = "a.txt", chunks = { "x" } } })
        tests.assertError(function() Upload.save(files.f, "a.txt", { upload_dir = TEMP_DIR }) end, "upload_root")
        tests.assertNil(Upload.save(files.f, ROOT .. "-sibling/a.txt", { upload_root = ROOT }))
        tests.assertNil(Upload.save({ path = "/etc/passwd", saved = true }, "a.txt", { upload_root = ROOT }))
        Upload.cleanup(files)
    end,
}

local ok = tests.runSuite("Uploads", suite)
for _, name in ipairs(list_dir(TEMP_DIR)) do os.remove(TEMP_DIR .. "/" .. name) end
os.remove(TEMP_DIR)
assert(ok)
