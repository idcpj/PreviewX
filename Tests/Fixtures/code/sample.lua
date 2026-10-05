-- Lua sample fixture
local preview = {
    name = "PreviewX",
    version = "1.0.0"
}

function preview.greet()
    print("Welcome to " .. preview.name)
end

preview.greet()
