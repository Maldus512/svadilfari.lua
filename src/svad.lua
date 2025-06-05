local svadilfari = require "svadilfari"
local utils = require "svadilfari.utils"

local fileExists = function(name)
    local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end

local getNinjaTargets = function(ninjaFile)
    local output = assert(io.popen(string.format("ninja -f %s -t targets", ninjaFile)), "Could not run ninja!")
    if output == nil then
        return {}
    end
    local targetLines = {}
    local line = output:read()
    while line do
        local target = string.match(line, "^(%S+):")
        table.insert(targetLines, target)
        line = output:read()
    end

    local _, _, code = output:close()
    if code ~= 0 then
        print("Could not query ninja for targets!")
    end
    return targetLines
end

local printHelp = function(commands, ninjaFilePath)
    print("Usage:")
    print("  svad [command|target]")
    print("")
    print("COMMANDS")
    print(string.format("  %-15s%s", "help", "Print this help"))
    print(string.format("  %-15s%s", "configure", "Configure the build"))
    print(string.format("  %-15s%s", "clean", "Clean the build"))
    print(string.format("  %-15s%s", "fullclean", "Delete all configuration files"))
    for _, command in ipairs(commands) do
        print(string.format("  %-15s%s", command.name, command.description))
    end
    print("")
    local targets = getNinjaTargets(ninjaFilePath)
    print(string.format("Ninja targets: %s", table.concat(targets, ", ")))
end

local main = function()
    local status, build = pcall(function() return require("build") end)

    if status then
        local ninjaFilePath = svadilfari.getOutputPath(build.output, build.buildFolder)

        if type(build) == "table" then
            if #arg > 0 and arg[1] == "help" then
                print(
                    "Svaðilfari, tireless horse that (almost) built the walls of Asgard is now at our service to build some software (with the help of a mercenary from feudal Japan)")
                print("")
                printHelp(build.commands or {}, ninjaFilePath)
            else
                if #arg == 0 then
                    if not fileExists(ninjaFilePath) then
                        print("Ninja file " .. ninjaFilePath .. " not found, creating...")
                        local configuration = svadilfari.new { output = build.output, buildFolder = build.buildFolder }
                        build.configure(configuration).export()
                    end
                    svadilfari.execvp("ninja", "-f", ninjaFilePath)
                elseif arg[1] == "configure" then
                    local configuration = svadilfari.new { output = build.output, buildFolder = build.buildFolder }
                    build.configure(configuration).export()
                elseif arg[1] == "clean" then
                    svadilfari.execvp("ninja", "-f", ninjaFilePath, "-t", "clean")
                elseif arg[1] == "fullclean" then
                    utils.fullclean { output = ninjaFilePath, buildFolder = build.buildFolder }
                else
                    local targets = getNinjaTargets(ninjaFilePath)
                    for _, target in ipairs(targets) do
                        if arg[1] == target then
                            svadilfari.execvp("ninja", "-f", ninjaFilePath, arg[1])
                        end
                    end

                    print("Unknown target: " .. arg[1])
                end
            end
        else
            print(string.format("build.lua should return a table of commands, found a %s instead!", type(build)))
        end
    else
        print("Could not open build.lua!")
        print(status, build)
    end
end

main()
