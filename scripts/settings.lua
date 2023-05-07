require('savable')
require('controls')

function createEmptyState()
    return {
        state = {
            ["enable-x-haven"] = false,
            address = "localhost",
            port = "8080",
            ["enable-end-of-round-looting"] = true,
            ["enable-highlight-current-figurines"] = true,
            ["enable-highlight-tiles-by-type"] = true,
            ["enable-automatic-scenario-layout"] = true,
            ["enable-automatic-narration"] = false
        }
    }
end

function getExpectedEntries()
    return {
        { "enable-x-haven",                     "checkbox" },
        { "address",                            "text" },
        { "port",                               "text" },
        { "enable-end-of-round-looting",        "checkbox" },
        { "enable-highlight-current-figurines", "checkbox" },
        { "enable-highlight-tiles-by-type",     "checkbox" },
        { "enable-automatic-scenario-layout",   "checkbox" },
        { "enable-automatic-narration",         "checkbox" }
    }
end
