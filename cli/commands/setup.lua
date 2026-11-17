-- `setup`: prepares a project cloned from the starter (or created by `new`)
-- for development, asking before each step:
--   1. git: a fresh history without the template's remote, optional own remote
--   2. database: MySQL user/password for the Docker stack, written to .env
--   3. docker: start the stack with hot reload (`run`)
local cli_output = require("crescent.utils.cli_output")
local fs = require("cli.fs")
local EnvFile = require("cli.env_file")
local Prompt = require("cli.prompt")
local Docker = require("cli.commands.docker")

local Setup = {}

local TEMPLATE_REMOTE = "crescent%-starter"
local FRAMEWORK_REMOTE = "crescent%-framework"
-- Development defaults from .env.example, replaced when credentials are set.
local DEFAULT_ROOT_PASSWORD = "crescent_root_dev_password"

local function capture(command)
    local handle = io.popen(command .. " 2>/dev/null")
    if not handle then return nil end
    local output = handle:read("*a") or ""
    handle:close()
    output = output:gsub("%s+$", "")
    return output
end

local function step(number, total, title)
    print("")
    print(cli_output.colors.bold .. string.format("[%d/%d] %s", number, total, title) .. cli_output.colors.reset)
end

local function git(arguments)
    return fs.execute("git " .. arguments .. " >/dev/null 2>&1")
end

local function git_init()
    if not git("init -q -b main") then
        if not git("init -q") then return false end
        git("symbolic-ref HEAD refs/heads/main")
    end
    return true
end

-- Remote URLs end up in a shell command: they are quoted, and anything with
-- whitespace or a leading "-" (an option) is refused.
function Setup.valid_remote(url)
    return type(url) == "string" and #url <= 512 and url:match("^[^%s%-][^%s]*$") ~= nil
end

-- MySQL user names become MYSQL_USER and a GRANT target.
function Setup.valid_db_user(user)
    return type(user) == "string" and #user <= 32 and user:match("^[%a_][%w_]*$") ~= nil and user:lower() ~= "root"
end

-- Passwords go to .env and through compose interpolation and a shell in the
-- MySQL init script: no whitespace, quotes, "$", "\", "`" or "#".
function Setup.valid_password(password)
    return type(password) == "string" and #password >= 8 and #password <= 128
        and password:match("^[%w%p]+$") ~= nil and password:match("[%$'\"\\`#]") == nil
end

local function setup_git()
    if not fs.execute("git --version >/dev/null 2>&1") then
        cli_output.print_warning("git is not installed: skipping")
        return true
    end

    local fresh = false
    if fs.is_dir(".git") then
        local origin = capture("git remote get-url origin")
        if origin == "" then origin = nil end
        if origin and origin:match(FRAMEWORK_REMOTE) then
            cli_output.print_error("this is the Crescent framework repository (origin " .. origin .. "): setup is for projects")
            return false
        end
        local commits = tonumber(capture("git rev-list --count HEAD")) or 0
        cli_output.print_info(string.format("This folder already has a git history (%d commit(s)%s)", commits,
            origin and (", origin " .. origin) or ""))
        local from_template = origin == nil or origin:match(TEMPLATE_REMOTE) ~= nil
        if Prompt.confirm("Start a fresh git history? This deletes .git", from_template) then
            if not fs.execute("rm -rf .git") then
                cli_output.print_error("unable to remove .git")
                return false
            end
            if not git_init() then
                cli_output.print_error("git init failed")
                return false
            end
            cli_output.print_success("Fresh git repository (branch main)")
            fresh = true
        elseif origin and origin:match(TEMPLATE_REMOTE) and Prompt.confirm("Remove the template remote (origin)?", true) then
            git("remote remove origin")
            cli_output.print_success("Removed remote origin")
        end
    else
        if not git_init() then
            cli_output.print_error("git init failed")
            return false
        end
        cli_output.print_success("Git repository created (branch main)")
        fresh = true
    end

    if fresh then
        if capture("git config user.email") == "" then
            cli_output.print_warning("git user.email is not set: skipping the initial commit")
            cli_output.print_code('git config --global user.name "Your Name"\ngit config --global user.email you@example.com')
        elseif git("add -A") and git("commit -q -m " .. fs.shell_quote("chore: initial commit")) then
            cli_output.print_success("Initial commit created (.env is git-ignored)")
        else
            cli_output.print_warning("unable to create the initial commit")
        end
    end

    local url = Prompt.ask("Remote repository URL? (e.g. git@github.com:you/app.git)", "skip")
    if url == "skip" then return true end
    while not Setup.valid_remote(url) do
        cli_output.print_error("invalid remote URL")
        url = Prompt.ask("Remote repository URL?", "skip")
        if url == "skip" then return true end
    end
    local verb = (capture("git remote") or ""):match("origin") and "set-url" or "add"
    if not git("remote " .. verb .. " origin " .. fs.shell_quote(url)) then
        cli_output.print_error("unable to set the remote")
        return false
    end
    cli_output.print_success("Remote origin: " .. url)
    if capture("git rev-parse --verify HEAD") ~= "" and Prompt.confirm("Push to origin now?", false) then
        if fs.execute("git push -u origin HEAD") then
            cli_output.print_success("Pushed to origin")
        else
            cli_output.print_warning("push failed: check the URL and your access, then run git push -u origin main")
        end
    end
    return true
end

local function setup_database()
    local created, err = EnvFile.ensure(".")
    if created == nil then
        cli_output.print_error("unable to create .env: " .. tostring(err))
        return false
    end
    local text = fs.read(".env")
    local with_secrets, secret_error = EnvFile.with_secrets(text)
    if not with_secrets then
        cli_output.print_error(secret_error)
        return false
    end
    if created then
        cli_output.print_success(".env created from .env.example with random APP_KEY and JWT_SECRET")
    elseif with_secrets ~= text then
        cli_output.print_success("Generated the missing APP_KEY/JWT_SECRET in .env")
    end
    text = with_secrets

    if not Prompt.confirm("Set the MySQL user and password for the Docker database?", true) then
        EnvFile.write(".", text)
        cli_output.print_info("Keeping the credentials in .env")
        return true
    end

    local user = Prompt.ask("Database user", EnvFile.get(text, "DB_USER") or "crescent")
    while not Setup.valid_db_user(user) do
        cli_output.print_error("use letters, digits and '_' (max 32), not root")
        user = Prompt.ask("Database user", "crescent")
    end

    local password
    repeat
        password = Prompt.secret("Database password", "empty = generate one")
        if password == nil or password == "" then
            password = EnvFile.random_secret(16)
            cli_output.print_success("Generated a random password (saved in .env)")
        elseif not Setup.valid_password(password) then
            cli_output.print_error("8-128 characters, no spaces, quotes, $, \\, ` or #")
            password = nil
        end
    until password

    local values = { DB_USER = user, DB_PASSWORD = password }
    local root_password = EnvFile.get(text, "DB_ROOT_PASSWORD")
    if root_password == nil or root_password == "" or root_password == DEFAULT_ROOT_PASSWORD then
        values.DB_ROOT_PASSWORD = EnvFile.random_secret(16)
    end
    local ok, write_error = EnvFile.write(".", EnvFile.set(text, values))
    if not ok then
        cli_output.print_error("unable to write .env: " .. tostring(write_error))
        return false
    end
    cli_output.print_success("Saved DB_USER/DB_PASSWORD" .. (values.DB_ROOT_PASSWORD and " and a random DB_ROOT_PASSWORD" or "") .. " in .env")

    if Docker.available() and Docker.mysql_volume_exists() then
        cli_output.print_warning("A MySQL volume already exists: MySQL only reads these credentials when the volume is created.")
        cli_output.print_info("To recreate it (deletes the Docker database data):")
        cli_output.print_code("docker compose down -v")
    end
    return true
end

local function setup_docker()
    if not Docker.available() then
        cli_output.print_warning("Docker is not installed: skipping (https://docs.docker.com/get-docker/)")
        return true, false
    end
    if not Prompt.confirm("Start the app with Docker now (hot reload)?", true) then
        return true, false
    end
    return Docker.run(), true
end

function Setup.run()
    cli_output.print_header("Crescent setup")
    if not fs.exists("app.lua") or not fs.exists(".env.example") then
        cli_output.print_error("run setup from the project root (app.lua and .env.example not found)")
        return false
    end
    cli_output.print_info("Press Enter to accept the default shown in parentheses.")

    step(1, 3, "Git")
    if not setup_git() then return false end
    step(2, 3, "Database (.env)")
    if not setup_database() then return false end
    step(3, 3, "Docker")
    local ok, started = setup_docker()
    if not ok then return false end

    print("")
    cli_output.print_success("Setup complete")
    if not started then
        cli_output.print_info("Start the app with hot reload when you are ready:")
        cli_output.print_code("lua cli.lua run")
    end
    cli_output.print_info("Next: lua cli.lua make:module Product  ·  lua cli.lua help")
    return true
end

return Setup
