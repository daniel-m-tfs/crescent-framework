local Adapter = {}
Adapter.__index = Adapter

local REQUIRED_METHODS = { "connect", "query", "execute", "transaction", "close" }

local function assert_driver(driver)
    if type(driver) ~= "table" then error("database adapter must be a table", 3) end
    for _, name in ipairs(REQUIRED_METHODS) do
        if type(driver[name]) ~= "function" then
            error("database adapter must implement " .. name .. "()", 3)
        end
    end
end

function Adapter.new(driver)
    assert_driver(driver)
    return setmetatable({ driver = driver }, Adapter)
end

function Adapter:is_adapter()
    return true
end

function Adapter:connect(...)
    return self.driver:connect(...)
end

function Adapter:query(...)
    return self.driver:query(...)
end

function Adapter:execute(...)
    return self.driver:execute(...)
end

function Adapter:transaction(...)
    return self.driver:transaction(...)
end

function Adapter:close(...)
    return self.driver:close(...)
end

return Adapter