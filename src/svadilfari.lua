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

return {
    find = utils.find,
    execvp = utils.execvp,
    getOutputPath = getOutputPath,

    ---@param extension string
    ---@return fun(string) string
    toExtension = function(extension)
        return function(input)
            return input:gsub("%.[^.]+$", "." .. extension)
        end
    end,

    ---@param args {output: string?, buildFolder: string?}
    new = function(args)
        args.output = getOutputPath(args.output, args.buildFolder)

        assert(type(args.output) == "string",
            "Ninja file output path must be a string, not " .. type(args.output))

        local self = {
            variables = {},
            rules = {},
            builds = {},
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

                environmentToString("", self.variables)
                coroutine.yield("\n\n")

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
                    if build.implicit then
                        coroutine.yield("| ")
                        for _, input in ipairs(build.implicit) do
                            coroutine.yield(input .. " ")
                        end
                    end
                    coroutine.yield("\n")

                    if build.variables then
                        environmentToString("    ", build.variables)
                    end
                    coroutine.yield("\n")
                end
            end)
        end

        ---@alias BuildArgs {inputs: string[]?, target: (string | fun(string): string), implicit: string[]?, variables: {[string]: string}?} | string

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
                    implicit = args.implicit,
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

            if args.name == nil then
                local command_start = args.command:match("^([%S]+).*")

                local var = command_start:match("%$([%S]+)")
                if var ~= nil then
                    command_start = command_start:gsub("%$" .. var, self.variables[var])
                end

                if command_start == nil then
                    command_start = tostring(args.command)
                end

                local counter = 1
                local rule_name = command_start

                while self.rules[rule_name] ~= nil do
                    rule_name = command_start .. "_" .. tostring(counter)
                    counter = counter + 1
                end

                args.name = rule_name
            end

            self.rules[args.name] = args
            local ruleName = args.name
            self.rules[args.name].name = nil

            return function(buildargs)
                return build(ruleName, buildargs)
            end
        end

        ---Add a rule to automatically generate a compilation database
        ---@param path string?
        local generateCompilationDatabase = function(path)
            local compDb = rule("ninja -f " .. args.output .. " -t compdb > $out")
            compDb(path or "build/compile_commands.json")
        end

        ---Establish a default target
        ---@param target string
        local default = function(target)
            self.file:write("default " .. target .. "\n")
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

        -- C specific configuration

        ---C compilation rule
        ---@param args {compiler: string, deps: string?, includes: string[]}
        local compile = function(args)
            assert(type(args.compiler) == "string", "The compiler command must be a string, not " .. type(args.compiler))
            assert(type(args.deps) == "string" or type(args.deps) == "nil", "The deps mode must be an optional string, not " .. type(args.deps))
            
        end

        return {
            variables = variables,
            aliases = aliases,
            rule = rule,
            build = build,
            default = default,
            generateCompilationDatabase = generateCompilationDatabase,
            export = export,
        }
    end,
}
