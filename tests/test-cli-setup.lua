package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local fs = require("cli.fs")
local EnvFile = require("cli.env_file")
local Prompt = require("cli.prompt")
local Setup = require("cli.commands.setup")
local Docker = require("cli.commands.docker")

local function temp_dir()
    local handle = io.popen("mktemp -d")
    local path = handle:read("*l")
    handle:close()
    return path
end

local function quietly(callback, ...)
    local original_print, original_write = print, io.write
    print = function() end
    io.write = function() end
    local ok, result = pcall(callback, ...)
    print, io.write = original_print, original_write
    if not ok then error(result, 0) end
    return result
end

-- Feeds `answers` to Prompt.input, one per question.
local function answering(answers, callback)
    local index = 0
    local original = Prompt.input
    Prompt.input = function()
        index = index + 1
        return answers[index]
    end
    local ok, result = pcall(quietly, callback)
    Prompt.input = original
    if not ok then error(result, 0) end
    return result, index
end

local function env_file_edits_keep_other_lines()
    local text = "# comment\nAPP_KEY=\nDB_USER=crescent\nDB_PASSWORD=\"old pass\"\n"
    tests.assertEquals(EnvFile.get(text, "DB_USER"), "crescent")
    tests.assertEquals(EnvFile.get(text, "DB_PASSWORD"), "old pass")
    tests.assertEquals(EnvFile.get(text, "APP_KEY"), "")
    tests.assertNil(EnvFile.get(text, "MISSING"))

    local updated = EnvFile.set(text, { DB_USER = "app", NEW_KEY = "1" })
    tests.assertEquals(updated, "# comment\nAPP_KEY=\nDB_USER=app\nDB_PASSWORD=\"old pass\"\nNEW_KEY=1\n")

    local secrets = EnvFile.with_secrets("APP_KEY=\nJWT_SECRET=keep\n")
    tests.assertEquals(#EnvFile.get(secrets, "APP_KEY"), 96)
    tests.assertEquals(EnvFile.get(secrets, "JWT_SECRET"), "keep")
    tests.assertNotEquals(EnvFile.random_secret(), EnvFile.random_secret())
    tests.assertEquals(#EnvFile.random_secret(16), 32)
end

local function env_file_ensure_never_overwrites()
    local root = temp_dir()
    local ok, err = pcall(function()
        local file = io.open(fs.join(root, ".env.example"), "w")
        file:write("APP_KEY=\nJWT_SECRET=\nDB_USER=crescent\n")
        file:close()
        tests.assertTrue(EnvFile.ensure(root))
        local first = fs.read(fs.join(root, ".env"))
        tests.assertEquals(#EnvFile.get(first, "JWT_SECRET"), 96)
        tests.assertFalse(EnvFile.ensure(root), "existing .env is kept")
        tests.assertEquals(fs.read(fs.join(root, ".env")), first)
    end)
    fs.execute("rm -rf " .. fs.shell_quote(root))
    if not ok then error(err, 0) end
end

local function setup_validation()
    for _, url in ipairs({ "git@github.com:me/app.git", "https://github.com/me/app.git", "/srv/git/app.git" }) do
        tests.assertTrue(Setup.valid_remote(url), url)
    end
    for _, url in ipairs({ "", "-uhack", "a b", "a\nb", nil }) do
        tests.assertFalse(Setup.valid_remote(url), tostring(url))
    end
    tests.assertTrue(Setup.valid_db_user("crescent"))
    tests.assertTrue(Setup.valid_db_user("app_user2"))
    for _, user in ipairs({ "root", "ROOT", "a-b", "1abc", "x;drop", string.rep("a", 33) }) do
        tests.assertFalse(Setup.valid_db_user(user), user)
    end
    tests.assertTrue(Setup.valid_password("S3nh@-Forte!"))
    for _, password in ipairs({ "short", "has space1", "dollar$1234", "quote'1234", "back\\slash1", "tick`12345", "hash#12345" }) do
        tests.assertFalse(Setup.valid_password(password), password)
    end
end

local function prompts_use_defaults()
    local answers = answering({ "", "n", "maybe", "yes", "  value  " }, function()
        return {
            Prompt.confirm("a", true),
            Prompt.confirm("b", true),
            Prompt.confirm("c", false),
            Prompt.ask("d", "default"),
        }
    end)
    tests.assertTableEquals(answers, { true, false, true, "value" })
    tests.assertEquals(answering({}, function() return Prompt.ask("end of input", "x") end), "x")
end

local function docker_options()
    tests.assertTableEquals(Docker.parse({}), {})
    tests.assertTableEquals(Docker.parse({ "--logs", "--fresh" }), { logs = true, fresh = true })
    tests.assertTableEquals(Docker.parse({ "-f" }), { logs = true })
    tests.assertNil(Docker.parse({ "--nope" }))
    tests.assertEquals(Docker.project_name("/tmp/My App.v2/"), "myappv2")
    tests.assertEquals(Docker.project_name("/srv/crescent-starter"), "crescent-starter")
end

assert(tests.runSuite("CLI setup", {
    env_file_edits_keep_other_lines = env_file_edits_keep_other_lines,
    env_file_ensure_never_overwrites = env_file_ensure_never_overwrites,
    setup_validation = setup_validation,
    prompts_use_defaults = prompts_use_defaults,
    docker_options = docker_options,
}))
