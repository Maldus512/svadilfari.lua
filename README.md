# Svaðilfari

> [...] he asked that they would give him leave to have the help of his stallion, which was called Svadilfari;
> [...] and it seemed very marvellous to the Æsir what great rocks that horse drew, for the horse did more rough work by half than did the wright.

Svadilfari (norren *eth* omitted for simplicity) is an ergonomic and modest build system configurator specialized for C projects. It relies on a small Lua library to specify the dependency graph and then generates a [Ninja](https://ninja-build.org/) configuration file. It offers a unified command-line entry point for configuration and building.

## Rationale

### Another One?

![https://imgs.xkcd.com/comics/standards.png](Yes, I'm creating yet another one)

Unlinke more modern programming languages C doesn't come with a built-in build system. \
A variety of tools try to cover the gap, but almost all of them commit the unforgivable sin of reinventing the programming language: creating a [DSL](https://en.wikipedia.org/wiki/Domain-specific_language) with convoluted syntax and questionable semantics to declare the build configuration.

At its core, a build configuration is a dependency graph between source files with compilation rules in between. A graph is a data structure. You know what's a great tool for constructing data structures? Programming languages.\
Programming languages also happen to be the main trade of programmers, the kind folks who are supposed to use build software in the first place. Given these premises, why so many people decided to opt out of them when creating the main interface for their build systems will remain a question for the ages.

There are a few alternatives that take the virtuous route (props to [Scons](https://scons.org/) and [Bang](https://codeberg.org/cdsoft/bang)), but in my opinion they are far too complex and obscure in their API. Svadilfari is, for all intents and purposes, nothing more than a Lua library, installable with `luarocks`. It exposes about a dozen of functions and expects very little knowledge. 

While Svadilfari can in principle work with any build process, it is constructed as C-specific. Most other languages already have a well definied tool that does the job better.

### Why Lua

Given that an existing languages is the best choice to implement the API, Lua was picked for three main reasons:

 1. It's dinamically typed (or statically [unityped](https://existentialtype.wordpress.com/2011/03/19/dynamic-languages-are-static-languages/) if you want to be "that" guy). Build configurations are tipically small and simple, not warranting complex type systems. Moreover, since their execution leads to a compilation their runtime becomes a compile time if you squint; my point being that runtime errors are less prevalent and impactful, allowing us to benefit from the lax dynamic nature of the interpreted context.

 2. It has a flexible syntax. When passing a single table as parameter one can omit parentheses, making for a declarative*-ish* syntax that kind looks like its own DSL.

```lua
local compile = config.rule {
    command = "gcc -c -o $out $in",
    deps = "gcc",
}
```

 3. It's fast:

```bash
$ time python -c "exit()"

real	0m0.026s
user	0m0.022s
sys	0m0.004s
$ time lua -e "os.exit()"

real	0m0.005s
user	0m0.004s
sys	0m0.001s
```

### Why Ninja

It is fast, simple, effective and a well deserved industry standard.

## Usage

Create a file named `build.lua` within the project's root. It is a Lua module and it's supposed to return a table with a few fields; the most important is `configure`, a lua function that receives a `config` table that can be used to (you guessed it) configure the project's build process: 

```lua
return {
    configure = function(config)
        local link = config.linkElf { linker = "gcc" }
        local executable = link {
            inputs = "hello.c",
            target = "hello"
        }

        config.command {
            name = "run",
            command = "./" .. executable,
            dependencies = executable,
        }

        config.default(executable)
    end
}
```

```bash
$ svad configure
$ svad run
[2/2] ./hello
Hello World!
```

## Documentation

The `svadilfari` module returns a table with the following fields:

 - `new`: Create a new configuration object. It takes a single table parameter, `{output: string?, buildFolder: string?}`; `output` is the optional name for the resulting ninja file and `buildFolder` an optional path for the directory where all build artifacts will be stored.
 - `find`: Looks for all files with a certain extension within a directory. it takes a single table parameter: `{path: string, extension: string?, recursive: bool}`. `path` is the target folder, `extension` is an optional file extension to use as filter and `recursive` specifies whether the search should continue in subfolders. it returns a list of file paths.
 - `execvp`: analogous to the omonimous C function. It takes a variadic list of strings constructing a command line and replaces the current process with the specified command.
 - `getOutputPath` converts a pair of optional `output` and `buildFolder` arguments and returns the computed ninja file path.
 - `toExtension` is an higher order function that takes a string specifying the required file extension (without the leading dot) and returns a function that converts a string to the aforementioned extension. e.g. `toExtension("o")("main.c") = "main.o"`

## Installing

Being a Lua library it can be installed with `luarocks`:

```bash
$ luarocks install https://raw.githubusercontent.com/Maldus512/svadilfari.lua/refs/heads/main/svadilfari-0.1-1.rockspec
```

By specifying a custom install location with `--tree` you can achieve an effect similar to Python's virtual environments:

```bash
$ luarocks install --tree .env https://raw.githubusercontent.com/Maldus512/svadilfari.lua/refs/heads/main/svadilfari-0.1-1.rockspec
$ eval $(luarocks --tree .env path)
$ svad
```

## TODO

 - [ ] Add APIs to automatically reconfigure and rebuild when `build.lua` or `build.ninja` are changed

