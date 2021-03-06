---------------------------------------------------------------------------
-- @author Uli Schlachter
-- @copyright 2010 Uli Schlachter
-- @release @AWESOME_VERSION@
-- @classmod gears.object
---------------------------------------------------------------------------

local setmetatable = setmetatable
local pairs = pairs
local type = type
local error = error
local properties = require("gears.object.properties")

local object = { properties = properties, mt = {} }

--- Verify that obj is indeed a valid object as returned by new()
local function check(obj)
    if type(obj) ~= "table" or type(obj._signals) ~= "table" then
        error("add_signal() called on non-object")
    end
end

--- Find a given signal
-- @param obj The object to search in
-- @param name The signal to find
-- @param error_msg Error message for if the signal is not found
-- @return The signal table
local function find_signal(obj, name, error_msg)
    check(obj)
    if not obj._signals[name] then
        error("Trying to " .. error_msg .. " non-existent signal '" .. name .. "'")
    end
    return obj._signals[name]
end

--- Add a signal to an object. All signals must be added before they can be used.
-- @param name The name of the new signal.
function object:add_signal(name)
    check(self)
    assert(type(name) == "string", "name must be a string, got: " .. type(name))
    if not self._signals[name] then
        self._signals[name] = {
            strong = {},
            weak = setmetatable({}, { __mode = "kv" })
        }
    end
end

--- Connect to a signal
-- @param name The name of the signal
-- @param func The callback to call when the signal is emitted
function object:connect_signal(name, func)
    assert(type(func) == "function", "callback must be a function, got: " .. type(func))
    local sig = find_signal(self, name, "connect to")
    assert(sig.weak[func] == nil, "Trying to connect a strong callback which is already connected weakly")
    sig.strong[func] = true
end

local function make_the_gc_obey(func)
    if _VERSION <= "Lua 5.1" then
        -- Lua 5.1 only has the behaviour we want if a userdata is used as the
        -- value in a weak table. Thus, do some magic so that we get a userdata.

        -- luacheck: globals newproxy getfenv setfenv
        local userdata = newproxy(true)
        getmetatable(userdata).__gc = function() end
        -- Now bind the lifetime of userdata to the lifetime of func. For this,
        -- we mess with the function's environment and add a table for all the
        -- various userdata that it should keep alive.
        local key = "_secret_key_used_by_gears_object_in_Lua51"
        local old_env = getfenv(func)
        if old_env[key] then
            -- Assume the code in the else branch added this and the function
            -- already has its own, private environment
            table.insert(old_env[key], userdata)
        else
            -- No table yet, add it
            local new_env = { [key] = { userdata } }
            setmetatable(new_env, { __index = old_env, __newindex = old_env })
            setfenv(func, new_env)
        end
        assert(_G[key] == nil, "Something broke, things escaped to _G")
        return userdata
    end
    -- Lua 5.2+ already behaves the way we want with functions directly, no magic
    return func
end

--- Connect to a signal weakly. This allows the callback function to be garbage
-- collected and automatically disconnects the signal when that happens.
-- @param name The name of the signal
-- @param func The callback to call when the signal is emitted
function object:weak_connect_signal(name, func)
    assert(type(func) == "function", "callback must be a function, got: " .. type(func))
    local sig = find_signal(self, name, "connect to")
    assert(sig.strong[func] == nil, "Trying to connect a weak callback which is already connected strongly")
    sig.weak[func] = make_the_gc_obey(func)
end

--- Disonnect to a signal
-- @param name The name of the signal
-- @param func The callback that should be disconnected
function object:disconnect_signal(name, func)
    local sig = find_signal(self, name, "disconnect from")
    sig.weak[func] = nil
    sig.strong[func] = nil
end

--- Emit a signal
--
-- @param name The name of the signal
-- @param ... Extra arguments for the callback functions. Each connected
--   function receives the object as first argument and then any extra arguments
--   that are given to emit_signal()
function object:emit_signal(name, ...)
    local sig = find_signal(self, name, "emit")
    for func in pairs(sig.strong) do
        func(self, ...)
    end
    for func in pairs(sig.weak) do
        func(self, ...)
    end
end

--- Returns a new object. You can call :emit_signal(), :disconnect_signal,
-- :connect_signal() and :add_signal() on the resulting object.
local function new()
    local ret = {}

    -- Copy all our global functions to our new object
    for k, v in pairs(object) do
        if type(v) == "function" then
            ret[k] = v
        end
    end

    ret._signals = {}

    return ret
end

function object.mt.__call(_, ...)
    return new(...)
end

--- Helper function to get the module name out of `debug.getinfo`.
-- @usage
--  local mt = {}
--  mt.__tostring = function(o)
--      return require("gears.object").modulename(2)
--  end
--  return setmetatable(ret, mt)
--
-- @tparam[opt=2] integer level Level for `debug.getinfo(level, "S")`.
--   Typically 2 or 3.
-- @treturn string The module name, e.g. "wibox.widget.background".
function object.modulename(level)
    return debug.getinfo(level, "S").source:gsub(".*/lib/", ""):gsub("/", "."):gsub("%.lua", "")
end

return setmetatable(object, object.mt)

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
