---@diagnostic disable: redefined-local


local utils = require("svadilfari.utils")

---Join filesystem paths
---@param ... string?[]
---@return string
local join = function(...)
    local args = { ... }
    local result = ""
    local first = true

    for _, path in ipairs(args) do
        if path ~= nil then
            if first then
                result = path
                first = false
            else
                result = result .. "/" .. path
            end
        end
    end
    result = string.gsub(result, "/+", "/")
    return result
end

local getOutputPath = function(output, buildFolder)
    assert(type(buildFolder) == "string" or type(buildFolder) == "nil",
        "Build folder path must be an optional string, not " .. type(output))

    if output == nil then
        if buildFolder ~= nil then
            output = join(buildFolder, "build.ninja")
        else
            output = "build.ninja"
        end
    end

    return output
end

---@param extension string
---@return fun(string): string
local toExtension = function(extension)
    return function(input)
        return input:gsub("%.[^.]+$", "." .. extension)
    end
end

return {
    find = utils.find,
    execvp = utils.execvp,
    getOutputPath = getOutputPath,
    toExtension = toExtension,

    ---@param args {output: string?, buildFolder: string?}
    new = function(args)
        args.output = getOutputPath(args.output, args.buildFolder)

        assert(type(args.output) == "string",
            "Ninja file output path must be a string, not " .. type(args.output))

        local self = {
            variables = {},
            rules = {},
            builds = {},
            default = nil,
        }

        local toStringGenerator = function()
            return coroutine.create(function()
                local environmentToString = function(indent, environment, ignore)
                    for key, value in pairs(environment) do
                        if key ~= ignore then
                            coroutine.yield(string.format("%s%s = %s\n", indent, key, value))
                        end
                    end
                end

                if #self.variables > 0 then
                    environmentToString("", self.variables)
                    coroutine.yield("\n\n")
                end

                for rule, attributes in pairs(self.rules) do
                    coroutine.yield(string.format("rule %s\n", rule))
                    coroutine.yield(string.format("    command = %s\n", attributes.command))
                    environmentToString("    ", attributes, "command")
                    coroutine.yield("\n")
                end
                coroutine.yield("\n")

                for _, build in pairs(self.builds) do
                    coroutine.yield("build " .. build.target .. ": " .. build.ruleName .. " ")
                    if build.inputs then
                        for _, input in ipairs(build.inputs) do
                            coroutine.yield(input .. " ")
                        end
                    end
                    if build.implicit and #build.implicit > 0 then
                        coroutine.yield("|")
                        for _, input in ipairs(build.implicit) do
                            coroutine.yield(" " .. input)
                        end
                    end

                    if build.variables then
                        coroutine.yield("\n")
                        environmentToString("    ", build.variables)
                    end
                    coroutine.yield("\n")
                end

                if self.default ~= nil then
                    coroutine.yield("default " .. self.default .. "\n")
                end
            end)
        end

        ---@alias BuildArgs {inputs: string[]?, target: (string | fun(string): string), implicit: (string | string[])?, variables: {[string]: string}?} | string

        ---Dependency graph edge
        ---@param ruleName string
        ---@param args BuildArgs
        ---@return string
        local build = function(ruleName, args)
            local target = nil
            if type(args) == "string" then
                args = { target = args }
            end

            if type(args.target) == "string" then
                target = args.target
            elseif (type(args.target) == "function") then
                assert(#args.inputs == 1, "A name transforming function must go with a single input")
                target = args.target(args.inputs[1])
            else
                assert(false, "target parameter must be string or function, is " .. type(args.target))
            end

            if self.buildFolder then
                target = join(self.buildFolder, target)
            end

            table.insert(self.builds,
                {
                    ruleName = ruleName,
                    inputs = args.inputs,
                    target = target,
                    implicit = type(args.implicit) == "table" and args.implicit or { args.implicit },
                    variables = args
                        .variables
                })

            ---@cast target string
            return target
        end

        ---Create a ninja rule
        ---@param args table | string
        ---@return fun(args: BuildArgs): string
        local rule = function(args)
            if type(args) == "string" then
                args = { command = args }
            end

            assert(args.command ~= nil, "Each rule must specify a command")

            -- Ensure the rule has a unique name
            local ruleName = args.name
            local command_start = args.command:match("^([%S]+).*")
            if command_start == nil then
                command_start = tostring(args.command)
            end

            local counter = 1

            if ruleName == nil then
                local var = command_start:match("%$([%S]+)")
                if var ~= nil then
                    assert(self.variables[var] ~= nil, "Variable \"" .. var .. "\" has not been defined!")
                    command_start = command_start:gsub("%$" .. var, self.variables[var])
                end

                ruleName = command_start
            end

            while self.rules[ruleName] ~= nil do
                ruleName = command_start .. "_" .. tostring(counter)
                counter = counter + 1
            end

            self.rules[ruleName] = args
            self.rules[ruleName].name = nil -- Name moves to table key, remove the entry

            return function(buildargs)
                return build(ruleName, buildargs)
            end
        end

        ---Add a rule to automatically generate a compilation database
        ---@param path string?
        ---@return string
        local generateCompilationDatabase = function(path)
            local compDb = rule("ninja -f " .. args.output .. " -t compdb > $out")
            return compDb(path or join(args.buildFolder, "compile_commands.json"))
        end

        ---Establish a default target
        ---@param target string
        local default = function(target)
            self.default = target
        end

        ---Finish up the configuration
        local export = function()
            if args.buildFolder ~= nil then
                utils.mkdir(args.buildFolder)
            end

            local file = assert(io.open(args.output, "w"), "Unable to open " .. args.output)

            local generator = toStringGenerator()

            while coroutine.status(generator) ~= "dead" do
                local _, value = coroutine.resume(generator)
                if value ~= nil then
                    file:write(value)
                end
            end

            file:close()
        end

        local variables = setmetatable({}, {
            __newindex = function(_, key, value)
                self.variables[key] = value
            end
        })

        local aliases = setmetatable({}, {
            __newindex = function(_, key, value)
                build("phony", { inputs = { value }, target = key })
            end
        })

        ---Create a command target
        ---@param args {name: string, command: string, dependencies: (string[] | string)?}
        local command = function(args)
            assert(type(args.command) == "string", "command parameter must be string, not " .. type(args.command))
            assert(type(args.dependencies) == "string" or type(args.dependencies) == "table",
                "dependencies parameter must be string or list, not " .. type(args.dependencies))

            rule {
                name = args.name,
                command = args.command
            } {
                    target = args.name,
                    implicit = args.dependencies,
                }
        end

        -- C specific configuration

        ---C compilation rule
        ---@param args {compiler: string, deps: string?, includes: string[] | string, cflags: string[] | string}
        ---@return fun(input: string): string
        local compileObject = function(args)
            assert(type(args.compiler) == "string", "The compiler command must be a string, not " .. type(args.compiler))
            assert(type(args.deps) == "string" or type(args.deps) == "nil",
                "The deps mode must be an optional string, not " .. type(args.deps))
            assert(type(args.includes) == "string" or type(args.includes) == "table",
                "The includes mode must be a string or a list, not " .. type(args.includes))
            assert(type(args.cflags) == "string" or type(args.cflags) == "table",
                "The cflags mode must be a string or a list, not " .. type(args.cflags))

            local commandLine = args.compiler
            if args.deps ~= nil then
                commandLine = commandLine .. " -MD -MF $out.d"
            end

            if args.cflags then
                local cflags = type(args.cflags) == "table" and args.cflags or { args.cflags }
                ---@cast cflags string[]
                for _, cflag in ipairs(cflags) do
                    commandLine = commandLine .. " " .. cflag
                end
            end

            if args.includes then
                local includes = type(args.includes) == "table" and args.includes or { args.includes }
                ---@cast includes string[]
                for _, include in ipairs(includes) do
                    commandLine = commandLine .. " -I" .. include
                end
            end

            local compile = rule {
                name = args.compiler .. "_compile",
                command = commandLine .. " -c -o $out $in",
                depfile = args.deps and "$out.d" or nil,
                deps = args.deps,
            }

            return function(input)
                return compile {
                    inputs = { input },
                    target = toExtension("o"),
                }
            end
        end

        ---C linking rule
        ---@param args {linker: string, libs: string[] | string}
        ---@return fun(args: BuildArgs): string
        local linkElf = function(args)
            assert(type(args.linker) == "string", "The linker command must be a string, not " .. type(args.linker))
            assert(type(args.libs) == "string" or type(args.libs) == "table",
                "The libs must be a string or a list, not " .. type(args.libs))

            local commandLine = args.linker .. " -o $out $in"

            if args.libs then
                local libs = type(args.libs) == "table" and args.libs or { args.libs }
                ---@cast libs string[]
                for _, lib in ipairs(libs) do
                    commandLine = commandLine .. " -l" .. lib
                end
            end

            return rule {
                name = args.linker .. "_link",
                command = commandLine,
            }
        end

        ---@alias Module ({path: string, recursive: boolean} | string)

        ---Compile all C sources and return an object list
        ---@param compilationRule fun(string): string
        ---@param modules Module[]
        ---@return string[]
        local buildSources = function(compilationRule, modules)
            modules = modules[1] ~= nil and modules or { modules }

            local objects = {}
            for _, module in ipairs(modules) do
                if type(module) == "string" then
                    local output = compilationRule(module)
                    table.insert(objects, output)
                else
                    for _, source in ipairs(utils.find { path = module.path, extension = "c", recursive = module.recursive }) do
                        local output = compilationRule(source)
                        table.insert(objects, output)
                    end
                end
            end

            return objects
        end

        return {
            -- Generic Ninja API
            variables = variables,
            aliases = aliases,
            rule = rule,
            build = build,
            default = default,
            command = command,

            -- C specific API
            generateCompilationDatabase = generateCompilationDatabase,
            compileObject = compileObject,
            linkElf = linkElf,
            buildSources = buildSources,

            -- Meta
            export = export,
        }
    end,
}
