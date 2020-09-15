#!/usr/bin/lua
--license:
--: pipadoc - Documentation extractor
--: Copyright (C)                        Pipapo Project
--:  2015, 2016, 2017, 2020              Christian Thaeter <ct@pipapo.org>
--:
--: This program is free software: you can redistribute it and/or modify
--: it under the terms of the GNU General Public License as published by
--: the Free Software Foundation, either version 3 of the License, or
--: (at your option) any later version.
--:
--: This program is distributed in the hope that it will be useful,
--: but WITHOUT ANY WARRANTY; without even the implied warranty of
--: MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--: GNU General Public License for more details.
--:
--: You should have received a copy of the GNU General Public License
--: along with this program.  If not, see <http://www.gnu.org/licenses/>.
-------------------------------------------------------------------------------------------------

--PLANNED: include operator, add a file to the processing list
--PLANNED: Version check for documents {BRACED VERSION 2} ...
--PLANNED: --disable-strsubst option .. NOSTRSUBST STRSUBST macros
--PLANNED: merge sections for sorting --#foo+bar+baz or something like this
--PLANNED+ base os.exit() on errors 0 if everything is fine (only notice displayed)
--PLANNED+ 1 when output might be incorrect because of failures
--PLANNED+ 2 when output could not be generated correctly
--PLANNED: how to silence strsubst-lang warnings on first pass strsubst?
--FIXME: asciidoctor incompatibilities



--------------------------
-- Variable Definitions --
--------------------------

GLOBAL = {
  --GLOBAL:nl {VARDEF NL}
  --GLOBAL:nl   The line-break character sequence, defaults to '\n' and
  --GLOBAL:nl   can be changed with the '--define' command-line option.
  NL = "\n",

  --GLOBAL:nil {VARDEF NIL}
  --GLOBAL:nil   Expands to an empty string.
  NIL = "",

  --GLOBAL:markup {VARDEF MARKUP}
  --GLOBAL:markup   The markup syntax (--markup option). This information used by pipadoc
  --GLOBAL:markup   for selecting the top level section and postprocessors. Other user
  --GLOBAL:markup   defined extensions may use it as well.
  MARKUP = "text",

  --GLOBAL:toplevel {VARDEF TOPLEVEL}
  --GLOBAL:toplevel   The toplevel section used for assembling the output.
  TOPLEVEL = "MAIN",

  --GLOBAL:maybe {MACRODEF MAYBE name}
  --GLOBAL:maybe   Results in 'name' when it is defined, otherwise in an empty string.
  --GLOBAL:maybe   Used to suppress the literal form and warnings on optional macros
  MAYBE = function(context, arg)
    if context[arg] then
      return strsubst(context, context[arg])
    else
      return false
    end
  end
}

local sections = {}

-- at what level it got turned off (off when not nil)
local condblock_disabled

local gcontext = setmetatable(
  {
    --context_file:file {VARDEF FILE}
    --context_file:file   The file or section name currently processed or some special annotation
    --context_file:file   in angle brackets (eg '<startup>') on other processing phases
    --context_preprocess:line {VARDEF LINE}
    --context_preprocess:line   Current line number of input or section, or indexing key
    --context_preprocess:line   Lines start at 1
    FILE = "<startup>"
  }, {__index = GLOBAL})

local args_done = false
local opt_verbose = 1
local opt_nodefaults = false
local opt_aliases = {}
local opt_inputs = {}
local opt_list_sections = nil
local opt_output = nil
--PLANNED: make opt_config a list
local opt_config = "pipadoc_config.lua"
local opt_config_set = false
local opt_dryrun = false






--------------------------------
-- Type Checks and Conversion --
--------------------------------

--api_typecheck:
--:
--: Type Checks
--: ^^^^^^^^^^^
--:
--: Assertions to check externally supplied data. On success 'var' will be returned
--: otherwise an assertion error is raised.
--:

--PLANNED: use lua debug library for logging and reporting (current function etc)

-- assert with corrected error context
local function assertx(flag, message)
  if not flag then
    error(message, 3)
  end
end

--PLANNED: make expected a list (to_table)
function assert_type(var, expected) --: checks that the 'var' is of type 'expected'
  assertx(type(var) == expected, "type error: "..expected.." expected, got "..type(var))
  return var
end

function maybe_type(var, expected) --: checks that the 'var' is of type 'expected' or nil
  assertx(var == nil or type(var) == expected, "type error: "..expected.." or nil expected, got "..type(var).. " >>>"..tostring(var).."<<<")
  return var
end

function assert_char(var) --: checks that 'var' is a single character
  assertx(type(var) == "string" and #var == 1, "type error: single character expected")
  return var
end

function assert_notnil(var) --: checks that 'var' is not 'nil'
  assertx(type(var) ~= "nil", "Value expected")
  return var
end

--api_typeconv:
--:
--: Type Conversions
--: ^^^^^^^^^^^^^^^^
--:
--: Functions which do specific conversions.
--:

function to_table(v) --: if 'v' is not a table then return +++\{v\}+++
  if type(v) ~= 'table' then
    return {v}
  else
    return v
  end
end

function maybe_text(v) --: convert 'v' to a string, returns 'nil' when that string would be empty
  v = tostring(v)
  if v ~= "" then
    return v
  else
    return nil
  end
end






----------------------
-- Helper Functions --
----------------------

local function args_check(arg, n)
  assert(#arg >= n, "missing arg: "..arg[n-1])
end

local function gcontext_set(file, line)
  assert_type(file, 'string')
  gcontext.FILE = file
  gcontext.LINE = line
end

--api_various:
function pattern_escape(s)  --: Escape all on alphanumeric characters in string 's' so that it can be used as verbatim pattern.
  return (s:gsub("%W", "%%%1"))
end


function string_tohex(s) --: Encode a string as sequence of 2-byte hex chars (useable as sorting key)
  local ret = ""
  for _, v in ipairs({string.byte(s, 1, #s)}) do
    ret = ret..string.format ("%02x", v)
  end
  return ret
end






--------------------------------
-- Error handling and logging --
--------------------------------

--PLANNED: log to PIPADOC_LOG section, later hooked in here
--PLANNED: use stdout when opt_output is set AND debugging is selected
--PLANNED: better/more diagnostic levels (s. syslog)
local printerr_hook

local function printerr(...)
  local args={...}
  local line = ""
  for i=1,#args do
    if i > 1 then
      line = line.."\t"
    end
    line = line..tostring(args[i] or "\t")
  end
  line = line.."\n"

  io.stderr:write(line)
  if printerr_hook then
    printerr_hook(line)
  end
end

local function printlvl(context,lvl,...)
  maybe_type(context, 'table')
  if lvl <= opt_verbose then
    context = context or gcontext
    printerr(context.FILE..":"..(context.LINE and context.LINE..":" or ""), ...)
  end
end


--api_logging:
--:
--: Logging Progress and Errors
--: ^^^^^^^^^^^^^^^^^^^^^^^^^^^
--:
--: Functions for to log progress and report errors. All this functions take a variable argument
--: list. Any argument passed to them will be converted to a string and printed to stderr when
--: the verbosity level is high enough.
--:
function warn(context,...) --: report a important but non fatal failure
  printlvl(context,1, ...)
end

function dbg(context,...) --: show debugging information
  printlvl(context,3, ...)
end

function trace(context,...) --: show more detailed progress information
  printlvl(context,4, ...)
end


function die(context, ...) --: report a fatal error and exit the program
  context = context or gcontext
  printerr(context.FILE..":"..(context.LINE and context.LINE..":" or ""), ...)
  os.exit(1)
end



-- debugging only
function table_dump(context, p, t)
  for k,v in pairs(t) do
    dbg(context, p, k,v)
    if type(v) == 'table' then
      table_dump(context, p.."/"..k, v)
    end
  end
end






----------------------------
-- Commandline Processing --
----------------------------

--api_various:
function inputfile_add(filename) --: Add a 'filename' to the list of files to process
  assert_type(filename, "string")
  opt_inputs[#opt_inputs+1] = filename
end

function alias_register(from, to) --: Register a new filetype alias.
  --:   See '--alias' for an example.
  --:   from:::
  --:     A pattern (possibly with a capture) matching unknown input filenames.
  --:   to:::
  --:     The replacement (possibly expanding the capture) to a known aliased filetype.
  --:
  assert_type(from, "string")
  assert_type(to, "string")
  dbg(nil, "register alias:", from, "->", to)
  opt_aliases[#opt_aliases+1] = {from, to}
end

local asciidoc_toolchain = [[
        FLAVOR="{MAYBE FLAVOR}"
        PDF="{MAYBE PDF}"
        ASCIIDOC=$(which asciidoc)
        A2X=$(which a2x)
        ASCIIDOCTOR=$(which asciidoctor)
        ASCIIDOCTOR_PDF=$(which asciidoctor-pdf)

        if test "$FLAVOR" = ""; then
          if test "$ASCIIDOCTOR"; then
            FLAVOR=asciidoctor
          elif test "$ASCIIDOC"; then
            FLAVOR=asciidoc
          else
            echo "neither asciidoc nor asciidoctor found"
            exit 1
          fi
          echo "autodetected $FLAVOR toolchain"
        elif test "$FLAVOR" = "asciidoctor" -a -z "$ASCIIDOCTOR"; then
            echo "asciidoctor not found"
            exit 1
        elif test "$FLAVOR" = "asciidoc" -a -z "$ASCIIDOC"; then
            echo "asciidoc not found"
            exit 1
        else
          echo "building doc using $FLAVOR toolchain"
        fi
]]

--usage:
local options = {
  "pipadoc [options...] [inputs..]",  --:  <STRING>
  "  options are:", --:  <STRING>

  "    -v, --verbose", --:  <STRING>
  "                        increment verbosity level", --:  <STRING>
  ["-v"] = "--verbose",
  ["--verbose"] = function ()
    opt_verbose = opt_verbose+1
    dbg(nil, "verbose:", opt_verbose)
  end,
  "", --:  <STRING>

  "    -q, --quiet", --:  <STRING>
  "                        suppresses any messages", --:  <STRING>
  ["-q"] = "--quiet",
  ["--quiet"] = function () opt_verbose = 0 end,
  "", --:  <STRING>

  "    -d, --debug", --:  <STRING>
  "                        set verbosity to debug level", --:  <STRING>
  "                        one additional -v enables tracing", --:  <STRING>
  ["-d"] = "--debug",
  ["--debug"] = function ()
    opt_verbose = 3
    dbg(nil, "verbose:", opt_verbose)
  end,
  "", --:  <STRING>

  "    -n, --dry-run", --:  <STRING>
  "                        don not generate output", --:  <STRING>
  ["-n"] = "--dry-run",
  ["--dry-run"] = function ()
    opt_dryrun = true
  end,
  "", --:  <STRING>

  "    -h, --help", --:  <STRING>
  "                        show this help", --:  <STRING>
  ["-h"] = "--help",
  ["--help"] = function ()
    usage()
  end,
  "", --:  <STRING>
  "    -r, --register <name> <file> <comment>", --:  <STRING>
  "                        register a filetype pattern", --:  <STRING>
  "                        for files matching a file pattern", --:  <STRING>
  ["-r"] = "--register",
  ["--register"] = function (arg,i)
    args_check(arg, i+3)
    filetype_register(arg[i+1], arg[i+2], arg[i+3])
    return 3
  end,
  "", --:  <STRING>

  "    -t, --toplevel <name>", --:  <STRING>
  "                        sets 'name' as toplevel node [MAIN]", --:  <STRING>
  ["-t"] = "--toplevel",
  ["--toplevel"] = function (arg, i)
    args_check(arg, i+1)
    GLOBAL.TOPLEVEL = arg[i+1]
    dbg(nil, "toplevel:", GLOBAL.TOPLEVEL)
    return 1
  end,
  "", --:  <STRING>

  "    -c, --config <name>", --:  <STRING>
  "                        selects a config file [pipadoc_config.lua]", --:  <STRING>
  ["-c"] = "--config",
  ["--config"] = function (arg, i)
    args_check(arg, i+1)
    opt_config = arg[i+1]
    opt_config_set = true
    dbg(nil, "config:", opt_config)
    return 1
  end,
  "", --:  <STRING>

  "    --no-defaults", --:  <STRING>
  "                        disables default filetypes and configfile loading", --:  <STRING>
  ["--no-defaults"] = function ()
    opt_nodefaults = true
    dbg(nil, "nodefaults")
  end,
  "", --:  <STRING>

  "    --list-sections", --:  <STRING>
  "                        Parses input and lists all sections on stdout", --:  <STRING>
  "                        appended with '[section]', '[keys]' or [section keys]'", --:  <STRING>
  "                        depending on the contents, includes '--dry-run'", --:  <STRING>
  ["--list-sections"] = function ()
    dbg(nil, "list-sections")
    opt_dryrun = true
    opt_list_sections = true
  end,
  "", --:  <STRING>

  "    -m, --markup <name>", --:  <STRING>
  "                        selects the markup engine for the output [text]", --:  <STRING>
  ["-m"] = "--markup",
  ["--markup"] = function (arg, i)
    args_check(arg, i+1)
    GLOBAL.MARKUP = arg[i+1]
    dbg(nil, "markup:", GLOBAL.MARKUP)
    return 1
  end,
  "", --:  <STRING>
  --PLANNED: integrate markup processor integration when -o is given and --format .pdf|.html etc are given (driven by config file)

  --PLANNED: multiple output files, associated with markup, toplevel and defines  --generate <config> somehow
  "    -o, --output <file>", --:  <STRING>
  "                        writes output to 'file' [stdout]", --:  <STRING>
  ["-o"] = "--output",
  ["--output"] = function (arg, i)
    args_check(arg, i+1)
    opt_output = arg[i+1]
    dbg(nil, "output:", opt_output)
    return 1
  end,
  "", --:  <STRING>

  "    -a, --alias <pattern> <as>", --:  <STRING>
  "                        aliases filenames to another filetype.", --:  <STRING>
  "                        for example, treat .install files as shell files:", --:  <STRING>
  "                         --alias '(.*)%.install' '%1.sh'", --:  <STRING>
  ["-a"] = "--alias",
  ["--alias"] = function (arg, i)
    args_check(arg, i+2)
    alias_register(arg[i+1], arg[i+2])
    return 2
  end,
  "", --:  <STRING>

  "    -D, --define <name>[=<value>]", --:  <STRING>
  "                        define a GLOBAL variable to value or 'true'", --:  <STRING>
  "    -D, --define -<name>", --:  <STRING>
  "                        undefine a GLOBAL variable", --:  <STRING>
  ["-D"] = "--define",
  ["--define"] = function (arg,i)
    args_check(arg, i+1)
    local key,has_value,value = arg[i+1]:match("^([%w_]+)(=?)(.*)")
    local undef = arg[i+1]:match("^[-]([%w_]+)")
    if undef then
      dbg(nil, "undef:", undef)
      GLOBAL[undef] = nil
    elseif key then
      if has_value == "" then
        value = 'true'
      end
      dbg(nil, "define:", key, value)
      GLOBAL[key] = value
    end
    return 1
  end,
  "", --:  <STRING>

  -- intentionally here undocumented, only works with properly set up development environment
  ["--make-doc"] = function (arg, i)
    opt_dryrun = true
    os.execute(strsubst(nil, asciidoc_toolchain .. [[
        lua pipadoc.lua -D FLAVOR="$FLAVOR" -m asciidoc pipadoc.lua pipadoc_config.lua -o pipadoc.txt

        if test "$FLAVOR" = "asciidoctor"; then
          "$ASCIIDOCTOR" -a webfonts! -a toc pipadoc.txt
          if test "$PDF" = "true"; then
            if test "$ASCIIDOCTOR_PDF"; then
              "$ASCIIDOCTOR_PDF" pipadoc.txt
            else
              echo "asciidoctor-pdf not found"
              exit 1
            fi
          fi
        elif test "$FLAVOR" = "asciidoc"; then
          asciidoc -a toc pipadoc.txt
          if test "$PDF" = "true"; then
            if test "$A2X"; then
              a2x -L -k -v --dblatex-opts "-P latex.output.revhistory=0" pipadoc.txt
            else
              echo "a2x not found"
              exit 1
            fi
          fi
        fi

        lua pipadoc.lua -m text -t README pipadoc.lua pipadoc_config.lua -o README
    ]], true))
  end,

  ["--eissues"] = function (arg, i)
    --PLANNED: run universally
    opt_dryrun = true
    os.execute [[
        lua pipadoc.lua -m text -D ISSUES -t ISSUES pipadoc.lua pipadoc_config.lua
    ]]
  end,

  ["--issues"] = function (arg, i)
    opt_dryrun = true
    os.execute(strsubst(nil, asciidoc_toolchain .. [[
       lua pipadoc.lua -D FLAVOR="$FLAVOR" -m asciidoc -D GIT -D ISSUES -t ISSUES pipadoc.lua pipadoc_config.lua -o pipadoc_issues.txt

       if test "$FLAVOR" = "asciidoctor"; then
          "$ASCIIDOCTOR" -a webfonts! pipadoc_issues.txt
       elif test "$FLAVOR" = "asciidoc"; then
          "$ASCIIDOC" pipadoc_issues.txt
       fi
    ]], true))
  end,

  "    --", --:  <STRING>
  "                        stops parsing the options and treats each", --:  <STRING>
  "                        following argument as input file", --:  <STRING>
  ["--"] = function () args_done=true end,

  --PLANNED: --list-filetypes
  --PLANNED: eat (double, triple, ..) empty lines (do this in a postprocessor)
  --PLANNED: add debug report (warnings/errors) to generated document PIPADOC_LOG section
  --PLANNED: wrap at blank/intelligent -> postprocessor
  --PLANNED: wordwrap
  --PLANNED: source indent with pretty printing --indent columns

  "", --:  <STRING>
  "  inputs are file names or a '-' that indicates standard input", --:  <STRING>
}



function usage()
  for i=1,#options do
    print(options[i])
  end
  os.exit(0)
end


function args_parse(arg)
  gcontext_set "<args_parse>"

  local i = 1
  while i <= #arg do
    gcontext.LINE=i
    while string.match(arg[i], "^%-%a%a+") do
      args_parse {"-"..string.sub(arg[i],2,2)}
      arg[i] = "-"..string.sub(arg[i],3)
    end

    if not options[arg[i]] then
      inputfile_add(arg[i])
    else
      local f = options[arg[i]]
      while options[f] do
        f = options[f]
      end
      if type(f) == 'function' then
        i = i + (f(arg, i) or 0)
      else
        die(nil, "optarg error")
      end
    end
    i = i+1
  end
end






---------------------
-- Library Loading --
---------------------

--api_load:
--:
--: Library Loading
--: ^^^^^^^^^^^^^^^
--:
function request(name) --: try to load optional modules
  --:    wraps Lua 'require' in a pcall so that failure to load module 'name' results in 'nil'
  --:    rather than a error.
  local ok,handle = pcall(require, name)
  if ok then
    dbg(nil, "loaded:", name, handle._VERSION)
    return handle
  else
    warn(nil, "can't load module"..":", name) --cwarn.<HEXSTRING>: <STRING> ::
    --cwarn.<HEXSTRING>:  'request()' failed to load a module.
    return nil
  end
end






--------------
-- Strsubst --
--------------

--api_strsubst:
--:
--: String Substitution Engine
--: ^^^^^^^^^^^^^^^^^^^^^^^^^^
--:
--api_strsubst_example:
--:
--: .Examples
--: ----
--: context = {
--:   STRING = "example string",
--:   STR = "\{STRING\}",
--:   ING = "ING",
--:   UPPER = function(context, arg)
--:             return arg:upper()
--:           end
--:  }
--:
--  Note: curly braces are escaped here to be kept in the generated documentation
--: -- simple substitution
--: assert(strsubst(context, "\{STRING\}") == "example string")
--:
--: -- arguments on stringish substitutions are retained
--: assert(strsubst(context, "\{STRING example\}") == "example stringexample")
--:
--: -- substitution is recursively applied
--: assert(strsubst(context, "\{STR\}") == "example string")
--:
--: -- that can be used to create names dynamically
--: assert(strsubst(context, "\{STR\{ING\}\}") == "example string")
--:
--: -- functions are called with the argument and their return is substituted
--: assert(strsubst(context, "\{UPPER arg\}") == "ARG")
--:
--: -- now together
--: assert(strsubst(context, "\{UPPER \{STR\}\}") == "EXAMPLE STRING")
--:
--: -- undefined names are kept verbatim
--: assert(strsubst(context, "\{undefined\}") == "\{undefined\}")
--: ----
--:

local function table_inverse(t)
  local ret = {}
  for k,v in pairs(t) do
    ret[v] = k
  end
  return ret
end

local strsubst_escapes = {
  ["\\"] = "{__BACKSLASH__}",
  ["`"] = "{__BACKTICK__}",
  ["{"] = "{__BRACEOPEN__}",
  ["}"] = "{__BRACECLOSE__}",
}

local strsubst_escapes_back = table_inverse(strsubst_escapes)


--api_strsubst:
function strsubst(context, str, escape) --: substitute text
  --:   context:::
  --:     The current context which defines all variables and
  --:     macros for the substitution.
  --:   str:::
  --:     The string to operate on.
  --:   escape:::
  --:     Rule for special character escaping.
  --:     true:::: handle escaping in one pass.
  --:     'escape':::: 1st pass, replaces escaped characters with a reserved internal representation.
  --:     'unescape':::: 2nd pass, turns the reserved internal representation of escaped characters back into the native form.
  --:     nil:::: no special escaping.
  --=api_strsubst_example
  trace(context, "strsubst:", str)
  maybe_type(context, "table")
  assert_type(str, "string")

  context = context or gcontext

  local function strsubst_intern(context, str)
    trace(context, "strsubst_intern:", str)

    return str:gsub("%b{}",
                    function (capture)
                      local macro, arg = capture:match("^{([%w_{}]*).?(.*)}$")
                      if macro then

                        if macro:match("%b{}") then
                          trace(context, "strsubst_intern expand macro:", macro)
                          macro = strsubst_intern(context_new(context), macro)
                        end

                        -- macro must be fully resolved
                        if not macro:match("%b{}") then

                          local expansion = context[macro]

                          if type(expansion) == 'string' then

                            if arg:match("%b{}") then
                              trace(context, "strsubst_intern expand arg:", arg)
                              arg = strsubst_intern(context_new(context), arg)
                            end

                            if expansion:match("%b{}") then
                              trace(context, "strsubst_intern expand macro:", macro)
                              return strsubst(context_new(context, {__ARG__ = arg}),
                                              expansion)
                            end

                            return expansion..arg

                          elseif type(expansion) == 'number' then
                            return tostring(expansion)

                          elseif type(expansion) == 'function' then
                            trace(context, "strsubst_intern expand function:", macro, arg)
                            local ok, result = pcall(expansion, context, arg)
                            if ok then
                              if result == true then
                                result = "true"
                              elseif type(result) == 'number' then
                                result = tostring(result)
                              end
                              return result or ""
                            else
                              warn(context, "strsubst function failed"..":", macro, result) --cwarn.<HEXSTRING>: <STRING> ::
                              --cwarn.<HEXSTRING>:  Tried to call a custom function from 'strsubst()' which failed.
                            end

                          elseif macro:match("^__[%w_]*__$") then
                            -- fallthrough __RESERVED__ name

                          elseif expansion == nil then
                            if escape ~= 'escape' then -- suppress warning on first pass
                              warn(context, "strsubst no expansion"..":", macro, escape)  --cwarn.<HEXSTRING>: <STRING> ::
                              --cwarn.<HEXSTRING>:  No substitution defined. Braced expression left verbatim.
                              --cwarn.<HEXSTRING>:  Possibly forgotten to escape the curly braces.
                            end
                          else
                            warn(context, "strsubst type error"..":", macro, type(expansion))  --cwarn.<HEXSTRING>: <STRING> ::
                            --cwarn.<HEXSTRING>:  string substitution expects a string, number or a function for expansion.
                          end
                        end
                      end

                      -- fallthrough return unaltered capture
                      return capture
                    end
    )
  end

  if escape == true or escape == 'escape' then
    str = strsubst_escape(str)
  end

  local ok, rstr = pcall(strsubst_intern, context, str)

  if not ok then
    warn(context, "strsubst error"..":", rstr) --cwarn.<HEXSTRING>: <STRING> ::
    --cwarn.<HEXSTRING>:  string substitution failed, possibly because of recursion limit.
  else
    str = rstr
  end

  if escape == true or escape == 'unescape'then
    str = strsubst_unescape(str)
  end

  trace(context, "strsubst done:", str)
  return str
end

function strsubst_escape(str) --: Turn escaped characters (backslash, backtick, curly braces) into an internal form.
  return str:gsub("[`\\]([{}\\])", strsubst_escapes)
end

function strsubst_unescape(str) --: Turn the internal escaped charaters into their literals.
  return str:gsub("%b{}", strsubst_escapes_back)
end


local function strsubst_run(context, escape)
  if context.TEXT then
    local subst = strsubst(context_new(context), context.TEXT, escape)

    -- drop lines
    if context.TEXT:match("^%b{}$") and subst == "" then
      context.TEXT = nil
    else
      context.TEXT = subst
    end
  end
end

function strsubst_strip_braces(str) --: removes the curly braces around an strsusbt result.
  --:   str:::
  --:     String to strip
  assert_type(str, 'string')
  return str:match("^%b{}$") and str:match("^{(.*)}$") or str
end


--api_strsubst_lang:
--:
--: String Substitution Language
--: ++++++++++++++++++++++++++++
--:
function strsubst_language_parse(context, source) --: parses 'source' into a list of
  --+  arguments. Evaluates arguments within curly braces.
  --:   context:::
  --:     The current context which defines all variables and macros.
  --:   source:::
  --:     The string to parse.
  --:   +return+:::
  --:     A list of parsed values
  assert_type(context, "table")
  assert_type(source, "string")
  trace(context, "strsubst_language_parse:", source)

  local function pmatch(context, source)
    local pos = 1

    return function ()
      local match, npos

      match, npos = source:match("^%s*(%b{})()", pos)
      if match then
        pos = npos
        match = strsubst_strip_braces(strsubst(context, match))
      else
        match, npos = source:match("^%s*([^%s{}]+)()", pos)
        pos = npos
      end
      return match
    end
  end

  local result = {}

  for value in pmatch(context, source) do
    table.insert(result, value)
  end

  -- lua 5.1 and luajit provide global unpack() not table.unpack()
  trace(context, "strsubst_language_parse result:", table.unpack and table.unpack(result) or unpack(result))
  return result
end





function strsubst_language_init(context) -- initialize the string substitution language

  --PLANNED: option for disabling strsubst language

  --strsubst_lang:
  --:
  --: Metasyntactic
  --: ^^^^^^^^^^^^^
  --:
  --: {MACRODEFSP LITERAL text...}
  --: Returns 'text' in literal, non evaluated form. Used to suppress
  --: recursive evaluation by other macros.
  --:
  context.LITERAL = function (context, arg)
    return arg
  end


  --: Macro Definitions
  --: ^^^^^^^^^^^^^^^^^
  --:
  --: {MACRODEF GLOBAL name value}
  --: Defines a global macro 'name' to 'value'.
  --: 'name' must be new and comply to the strsusbt naming rules. Redefining existing names
  --: yields an error. Results in an empty string. Since setting globals to new values is not
  --: supported, this can only be used to set constants.
  --:
  context.GLOBAL = function (context, arg)
    local args = strsubst_language_parse(context, arg)

    local name = args[1]

    if name and name:match("^%a[%w_]*$") then
      local value = args[2] or ""

      if context[name] == nil then
        GLOBAL[name] = value
      else
        warn(nil, "macro already defined"..":", name) --cwarn.<HEXSTRING>: <STRING> ::
        --cwarn.<HEXSTRING>:  Redefining an already existing macro is not allowed.
      end
    else
      warn(nil, "no valid name"..":", name) --cwarn.<HEXSTRING>: <STRING> ::
      --cwarn.<HEXSTRING>:  GLOBAL or DEFINE called with non alphanumeric name
    end
  end


  --:
  --: {MACRODEF DEFINE name value}
  --: Defines a local macro 'name' to 'value'.
  --: 'name' must be new, redefining existing names yields an error.
  --:
  context.DEFINE = function (context, arg)
    local args = strsubst_language_parse(context, arg)

    local name = args[1]

    if name and name:match("^%a[%w_]*$") then
      local value = args[2] or ""

      if context[name] == nil then
        context[name] = value
      else
        warn(nil, "macro already defined"..":", name)
      end
    else
      warn(nil, "no valid name"..":", name)
    end
  end


  --:
  --: {MACRODEF SET name value}
  --: Assigns a local macro 'name' to 'value'.
  --: 'name' must be in the current scope. When 'name' does not exist yet it is created as
  --: with DEFINE.
  --:
  context.SET = function (context, arg)
    local args = strsubst_language_parse(context, arg)

    local name = args[1]

    if name and name:match("^%a[%w_]*$") then
      local value = args[2] or ""

      if context[name] == nil or rawget(context, name) then
        context[name] = value
      else
        warn(nil, "macro already defined"..":", name)
      end
    else
      warn(nil, "no valid name"..":", name)
    end
  end


  --:
  --: Control Structures
  --: ^^^^^^^^^^^^^^^^^^
  --:
  --: {MACRODEFSP DO text...}
  --:   Creates a local context, any variables defined within 'text...' are contained within this context.
  --:
  context.DO = function (context, arg)
     return strsubst(context_new(context), arg)
  end


  --: {MACRODEF IF condition {BRACED THEN ...} {BRACED ELSE ...}}
  --:   'condition' must be a predicate see <<Predicates,below>>.
  --:   When 'condition' is true then the 'THEN' part gets substituted otherwise the 'ELSE' part
  --:   gets substituted. The 'THEN' and 'ELSE' parts are optional.
  --:
  context.IF = function (context, arg)
    local args = strsubst_language_parse(context, arg)

    if #args < 1 then
      warn(nil, "IF condition missing"..":", name) --cwarn.<HEXSTRING>: <STRING> ::
      --cwarn.<HEXSTRING>:  The IF statement needs a condition to branch upon.
    else
      if #args[1] > 0 then
        return rawget(context, '__THEN__') and strsubst(context, rawget(context, '__THEN__')) or ""
      else
        return rawget(context, '__ELSE__') and strsubst(context, rawget(context, '__ELSE__')) or ""
      end
    end
  end


  --: {MACRODEFSP THEN ...when true...}
  --:   Defines the alternative to substitute inside an IF block when the 'condition' was
  --:   true.
  --:
  context.THEN = function (context, arg)
    rawset(context, '__THEN__', arg)
  end


  --: {MACRODEFSP ELSE ...when false...}
  --:   Defines the alternative to substitute inside an IF block when the 'condition' was not true.
  --:
  context.ELSE = function (context, arg)
    rawset(context, '__ELSE__', arg)
  end


  --: [[Predicates]]
  --: Predicates
  --: ^^^^^^^^^^
  --:
  --: Predicates take a list of arguments and evaluate to a truth value. In strsubst *true* is
  --: any non-empty text and *false* is an empty string. The string substitution engine will
  --: convert bool types and 'nil' into respective strings.
  --:
  --:
  --: Boolean
  --: +++++++
  --:
  --: {MACRODEFSP BOOL text}
  --:   Evaluates 'text' and then returns *true* when the resulting string would contain any
  --:   text or *false* for an empty string.
  --:
  context.BOOL = function (context, arg)
    arg = strsubst_strip_braces(strsubst(context, arg))
    if #arg > 0 then
      return true
    end
  end


  --: {MACRODEFSP NOT arg}
  --:   Evaluates 'arg' and then returns *false* when the resulting string would contain any text
  --:   or *true* in case of an empty string.
  --:
  context.NOT = function (context, arg)
    arg = strsubst_strip_braces(strsubst(context, arg))
    if #arg == 0 then
      return true
    end
  end


  --: {MACRODEF OR arguments...}
  --:   Results in 'true' when one of the arguments is *true*.
  --:
  context.OR = function (context, arg)
    local args = strsubst_language_parse(context, arg)
    for i=1,#args do
      if #args[i] > 0 then
        return true
      end
    end
  end


  --: {MACRODEF AND arguments...}
  --:   Results in 'false' when one of the arguments is *false*.
  --:
  context.AND = function (context, arg)
    local args = strsubst_language_parse(context, arg)
    for i=1,#args do
      if #args[i] == 0 then
        return false
      end
    end
    return true
  end


  --:
  --: Numeric
  --: +++++++
  --:
  --: Trying to convert the operands to a number, if that fails 0 is used.
  --: At least 2 arguments must be given.
  --: These predicates take a list of arguments and compare them left to right
  --: Resulting in the truth value of the comparsion.
  --:
  --: {MACRODEF EQ numbers...}
  --:   Results in *true* when all numbers are equal.
  --:
  context.EQ = function (context, arg)
    local args = strsubst_language_parse(context, arg)

    if #args < 2 then
      warn(nil, "missing argument"..":", name) --cwarn.<HEXSTRING>: <STRING> ::
      --cwarn.<HEXSTRING>:  Macro needs more arguments.
    else
      for i=2,#args do
        if (tonumber(args[1]) or 0) ~= (tonumber(args[i]) or 0) then
          return false
        end
      end
      return true
    end
  end


  --: {MACRODEF LE numbers...}
  --:   Compare numerically less or equal. 'numbers' must be a sequence of increasing or same
  --:   magnitude.
  --:
  context.LE = function (context, arg)
    local args = strsubst_language_parse(context, arg)

    if #args < 2 then
      warn(nil, "missing argument"..":", name)
    else
      for i=2,#args do
        if (tonumber(args[i-1]) or 0) > (tonumber(args[i]) or 0) then
          return false
        end
      end
      return true
    end
  end


  --: {MACRODEF GT numbers...}
  --:   Compare for greater than. 'numbers' must be a sequence of decreasing magnitude.
  --:
  context.GT = function (context, arg)
    local args = strsubst_language_parse(context, arg)

    if #args < 2 then
      warn(nil, "missing argument"..":", name)
    else
      for i=2,#args do
        if (tonumber(args[i-1]) or 0) <= (tonumber(args[i]) or 0) then
          return false
        end
      end
      return true
    end
  end


  --:
  --: Strings
  --: +++++++
  --:
  --: Compare the operands as string. At least 2 arguments must be given.
  --: These predicates take a list of arguments and compare them left to right
  --: Resulting in the truth value of the comparsion.
  --:
  --: {MACRODEF EQUAL strings...}
  --:   Results in *true* when all strings are equal.
  --:
  context.EQUAL = function (context, arg)
    local args = strsubst_language_parse(context, arg)

    if #args < 2 then
      warn(nil, "missing argument"..":", name)
    else
      for i=2,#args do
        if args[1] ~= args[i] then
          return false
        end
      end
      return true
    end
  end


  --: {MACRODEF SORTED strings...}
  --:   Compare strings for increasing or same sorting order.
  --:
  context.SORTED = function (context, arg)
    local args = strsubst_language_parse(context, arg)

    if #args < 2 then
      warn(nil, "missing argument"..":", name)
    else
      for i=2,#args do
        if args[i-1] > args[i] then
          return false
        end
      end
      return true
    end
  end


  --:
  --: Definitions
  --: +++++++++++
  --:
  --: {MACRODEF DEFINED macronames...}
  --:   Results in 'true' when all 'macronames' are defined.
  --:
  context.DEFINED = function (context, arg)
    local args = strsubst_language_parse(context, arg)
    for i=1,#args do
      if context[args[i]] == nil then
        return false
      end
    end
    return true
  end


  --: {MACRODEF HAVE sectiondescs...}
  --:   Results in 'true' when all sections described by 'sectiondescs' contains text.
  --:   'sectiondesc' is an optional sorting or pasting operator followed by a section name.
  --:   For example '{BRACED HAVE #items}' would be true if 'items' sorted numerically by
  --:   their key would result in at least one entry.
  --:
  context.HAVE = function (context, arg)
    local args = strsubst_language_parse(context, arg)
    for i=1,#args do
      local op, section = args[i]:match("(%p?)(.*)")
      if not sections[section] then
        return false
      end
      if op == "" or op == "=" then
        -- plain/past section
        if #sections[section] == 0 then
          return false
        end
      else
        -- op sorted
        if output_sort(sections[section], op) == 0 then
          return false
        end
      end
    end
    return true
  end


  --: {MACRODEF HAVENOT sectiondescs...}
  --:   Results in 'true' when all sections described by 'sectiondescs' are empty.
  --:   'sectiondesc' is an optional sorting or pasting operator followed by a section name.
  --:
  context.HAVENOT = function (context, arg)
    local args = strsubst_language_parse(context, arg)
    for i=1,#args do
      local op, section = args[i]:match("(%p?)(.*)")
      if sections[section] then
        if op == "" or op == "=" then
          -- plain/past section
          if #sections[section] > 0 then
            return false
          end
        else
          -- op sorted
          if output_sort(sections[section], op) > 0 then
            return false
          end
        end
      end
    end
    return true
  end


  -- :
  -- : .String Functions
  -- :
  -- : {MACRODEFSP LENGTH ...}
  -- :   Results in the length of the argument string in bytes as decimal number.
  -- :
  --PLANNED: context.LENGTH = function (context, arg)
  --   return tostring(#arg)
  -- end

  -- : .Section Metadata
  --PLANNED: context.NUM_ENTRIES = function (context, arg)
  -- end

  --PLANNED: UPPER LOWER
end






----------------------
-- Section handling --
----------------------

--sections:
--: Text in pipadoc is stored in named 'sections' and can be associated with some additional
--: alphanumeric key under that section. This enables later sorting for indices and glossaries.
--:
--: One-line sections are defined when a section and maybe a key is followed by documentation
--: text. One-line doctext can be interleaved into Blocks.
--:
--: At the start if a input file the default block section name is made from the files name
--: up to the first dot.
--:
--: Sections are later brought into the desired order by pasting them into a 'toplevel' section.
--: This default name for the 'toplevel' section is 'MAIN_{BRACED markup}' or if that does not exist
--: just 'MAIN'.
--:

--api_sections:
--:
--: Sections
--: ^^^^^^^^
--:

function section_append(section, key, context) --: Append data to the given section/key
  --:   to be called from preprocessors or macros which generate new content.
  --:
  --:   section:::
  --:     name of the section to append to, must be a string
  assert_type(section, "string")
  --:   key:::
  --:     the sub-key for sorting within that section. 'nil' for appending text to normal sections
  maybe_type(key, "string")
  --:   context:::
  --:     The source line broken down into its components and additional pipadoc metadata
  assert_type(context, "table")
  --:
  trace(context, "append:", section.."."..(key or "-"), context.TEXT)
  sections[section] = sections[section] or {keys = {}}
  if key then
    sections[section].keys[key] = sections[section].keys[key] or {}
    table.insert(sections[section].keys[key], context)
  else
    table.insert(sections[section], context)
  end
end

function section_concat(section, key, context) --: Concat 'context.TEXT' to the given
  --:   last entrys context already stored under section/key.
  --:
  --:   section:::
  --:     name of the section to append to, must be a string
  assert_type(section, "string")
  --:   key:::
  --:     the sub-key for sorting within that section. 'nil' for appending text to normal sections
  maybe_type(key, "string")
  --:   context:::
  --:     The source line broken down into its components and additional pipadoc metadata
  assert_type(context, "table")
  --:
  trace(context, "concat:", section.."."..(key or "-"), context.TEXT)
  sections[section] = sections[section] or {keys = {}}
  if key then
    sections[section].keys[key] = sections[section].keys[key] or {}

    local last = #sections[section].keys[key]
    if last > 0 then
      sections[section].keys[key][last].TEXT = sections[section].keys[key][last].TEXT .. context.TEXT
    else
      table.insert(sections[section].keys[key], context)
      -- tweak OP, there is no generator for '+'
      context.OP = ':'
    end
  else

    local last = #sections[section]
    if last > 0 then
      sections[section][last].TEXT = sections[section][last].TEXT .. context.TEXT
    else
      table.insert(sections[section], context)
      context.OP = ':'
    end
  end
end

function section_list() --: lists all sections
  local sections_sorted = {}

  for k in pairs(sections) do
    table.insert(sections_sorted, k)
  end

  table.sort(sections_sorted, function(a,b) return tostring(a):lower() < tostring(b):lower() end)

  local result = {}

  for i=1,#sections_sorted do
    local has_section = #sections[sections_sorted[i]] > 0
    local has_keys = pairs(sections[sections_sorted[i]].keys)(sections[sections_sorted[i]].keys) and true

    if has_section and has_keys then
      table.insert(result, sections_sorted[i] .. " [section keys]")
    elseif has_section then
      table.insert(result, sections_sorted[i] .. " [section]")
    elseif has_keys then
      table.insert(result, sections_sorted[i] .. " [keys]")
    end
  end

  return result
end






---------------
-- Filetypes --
---------------

--filetypes:
--: Pipadoc needs to know about the syntax of line comments of the files it is reading.
--: For this patterns are registered to be matched against the file name together with a
--: list of line comment characters.
--:
--: Definitions for a common programming languages are already included. For languages
--: that support block comments the opening (but not the closing) commenting characters are
--: registered as well. This allows one to define section blocks right away. Note that using
--  the  comment closing sequence on a popadoc comment the line will appear on the output.
--:
--{NOT {EQUAL {TOPLEVEL} README}
--: .Example in C
--: ----
--: /*blocksection:
--: //: this is a block-section
--: //: line comment sequences inside the block comment are still required
--: */
--:
--: /*works_too: but looks ugly
--: */
--:
--: // the following will include the closing */ in the documentation
--: /*fail: don't do this, pipadoc comments span to the end of the line */
--: ----
--:
--: A special case is that when a line comment is defined as an empty string ("") then every
--: line of a file is considered as documentation but no special operations apply. This is used
--: for plain text documentation files. These use the "PIPADOC:" keyword to enable special
--: operations within text files.
--:
--: New filetypes can be added from a config file with 'filetype_register()'  or with
--: the '--register' command-line option.
--:
--}
local filetypes = {}

--api_filetypes:
--:
--: Filetypes
--: ^^^^^^^^^
--:
function filetype_register(name, filep, linecommentseqs) --: Register a new filetype
  --:     name:::
  --:       mnemonic name of the language
  --:     filep:::
  --:       a Lua pattern or list of patterns matching filename
  --:     linecommentseqs:::
  --:       a string or list of strings matching comments of the registered filetype
  --:
  --: For example, C and C++ Filetypes are registered like:
  --:
  --: ----
  --: filetype_register("C",
  --:                   \{"%.c$","%.cpp$","%.C$", "%.cxx$", "%.h$"\},
  --:                   \{ "//", "/*"\})
  --: ----
  --:
  assert_type(name, "string")

  filep = to_table(filep)
  for _,v in pairs(filep) do
    assert_type(v, "string")
  end

  linecommentseqs = to_table(linecommentseqs)
  for _,v in pairs(linecommentseqs) do
    assert_type(v, "string")
  end

  for i=1,#filep do
    filetypes[filep[i]] = filetypes[filep[i]] or {language = name, comments = {}}
    for j=1,#linecommentseqs do
      dbg(nil, "register filetype:", name, filep[i], linecommentseqs[j])
      filetypes[filep[i]].comments[#filetypes[filep[i]].comments + 1] = linecommentseqs[j]
    end
  end
end

local function filetype_get(filename)
  assert_type(filename, "string")
  for k,v in pairs(filetypes) do
    if filename:match(k) then
      return v,k
    end
  end
end

local function comment_select(line, filetype)
  for i=1,#filetype.comments do
    local comment = pattern_escape(filetype.comments[i])
    if string.match(line, comment) then
      return comment
    end
  end
end






------------------
-- Preprocessor --
------------------

local preprocessors = {}
--api_preproc:
--:
--: Preprocessors
--: ^^^^^^^^^^^^^
--:
function preprocessor_register(langpat, preprocess) --: register a preprocessor
  --:   langpat:::
  --:     Register preprocessor to all filetypes whose mnemonic matches 'langpat'.
  --:     Matches all languages when 'nil'.
  --:   preprocess:::
  --:     The preprocessor to register. Can be one of:
  --:     `function (context) ... end` ::::
  --:       Preprocessors may store state or have other side effect using API functions.
  --:       Takes the context of the current source line and shall return:
  --:       * the preprocessed line (complete 'SOURCE' line)
  --:       * false to drop the line
  --:       * true to keep the line unaltered
  --:     +\{pattern, repl [, n]\}+ ::::
  --:       Generates a function calling 'context.SOURCE:gsub(pattern, repl [, n])' for preprocessing.
  --:
  --PLANNED: langpat as list of patterns
  maybe_type(langpat, "string")
  langpat = langpat or ""
  dbg(nil, "register preprocessor:", langpat, preprocess)

  if type(preprocess) == "table" then
    local params = preprocess
    preprocess = function (context)
      local result = context.SOURCE:gsub(params[1], params[2], params[3])
      if result == context.SOURCE then
        return true
      end
      return result
    end
  end

  if type(preprocess) == "function" then
    table.insert(preprocessors, {pattern=langpat, preprocessor=preprocess})
  else
    warn(nil, "unsupported preprocessor type") --cwarn.<HEXSTRING>: <STRING> ::
    --cwarn.<HEXSTRING>:  Tried to 'preprocessor_register()' something that is not a function or table.
  end
end

-- internal, hook preprocessors into the filetype descriptors
local function preprocessors_attach()
  for i=1,#preprocessors do
    local ppdesc = preprocessors[i]
    for k,v in pairs(filetypes) do
      if ppdesc.pattern == "" or v.language:match(ppdesc.pattern) then
        local filetype_preprocessors = v.preprocessors or {}
        local skip = false
        for i=1,#filetype_preprocessors do
          if filetype_preprocessors[i] == ppdesc.preprocess then
            skip = true
            break
          end
        end
        if not skip then
          trace(nil, "add preprocessor for:", k, ppdesc.preprocessor)
          table.insert(filetype_preprocessors, ppdesc.preprocessor)
          v.preprocessors = filetype_preprocessors
        end
      end
    end
  end
end


local function preprocessors_run(preprocessors, context)
  if preprocessors then
    for i=1,#preprocessors do
      local ok,result = pcall(preprocessors[i], context)
      if not ok then
        warn(context, "preprocessor failed"..":", result) --cwarn.<HEXSTRING>: <STRING> ::
        --cwarn.<HEXSTRING>:  Preprocessor function error.
        --PLANNED: preprocessors may expand to multiple lines? return table
      elseif type(result) == 'string' then
        trace(context, "preprocessed:", context.SOURCE, "->", result)
        context.SOURCE = result
      elseif result == false then
        trace(context, "preprocessed drop:", context.SOURCE)
        context.SOURCE = nil
        break
      elseif result == true then
        -- NOP
      else
        warn(context, "preprocessor returned wrong type"..":", preprocessors[i], type(result)) --cwarn.<HEXSTRING>: <STRING> ::
        --cwarn.<HEXSTRING>:  Preprocessor returned unsupported type (or nil).
      end
    end
  end
end






-------------------
-- Postprocessor --
-------------------

local postprocessors = {}
--api_postproc:
--:
--: Postprocessors
--: ^^^^^^^^^^^^^^
--:
function postprocessor_register(markuppat, postprocess) --: register a postprocessor
  --:   markuppat:::
  --:     Register postprocessor to all markups whose name matches 'markuppat'.
  --:     Matches all markups when 'nil'.
  --:   postprocess:::
  --:     The postprocessor to register. Can be one of:
  --:     `function (context) ... end` ::::
  --:       Postprocessors may store state or have other side effect using API functions.
  --:       Takes the context of the current source line and shall return:
  --:       * the postprocessed line (the documentation comment part 'TEXT')
  --:       * false to drop the line
  --:       * true to keep the line unaltered
  --:     +\{pattern, repl [, n]\}+ ::::
  --:       Generates a function calling 'context.TEXT:gsub(pattern, repl [, n])' for postprocessing.
  --:
  --PLANNED: markuppat as list of patterns
  maybe_type(markuppat, "string")
  markuppat = markuppat or ""
  dbg(nil, "register postprocessor:", markuppat, postprocess)

  if type(postprocess) == "table" then
    local params = postprocess
    postprocess = function (context)
      local result = context.TEXT:gsub(params[1], params[2], params[3])
      if result == context.TEXT then
        return true
      end
      return result
    end
  end

  if type(postprocess) == "function" then
    table.insert(postprocessors, {pattern=markuppat, postprocessor=postprocess})
  else
    warn(nil, "unsupported postprocessor type") --cwarn.<HEXSTRING>: <STRING> ::
    --cwarn.<HEXSTRING>:  Tried to 'postprocessor_register()' something that is not a function or table.
  end
end


local active_postprocessors = {}

local function postprocessors_attach()
  for i=1,#postprocessors do
    local ppdesc = postprocessors[i]
    if GLOBAL.MARKUP:match(ppdesc.pattern) then
      trace(nil, "add postprocessor for:", GLOBAL.MARKUP, ppdesc.postprocessor)
      table.insert(active_postprocessors, ppdesc.postprocessor)
    end
  end
end

local function postprocessors_run(context)
  for i=1,#active_postprocessors do
    local ok, result = pcall(active_postprocessors[i], context)
    if not ok then
      warn(context, "postprocessor failed"..":", result) --cwarn.<HEXSTRING>: <STRING> ::
      --cwarn.<HEXSTRING>:  Postprocessor function error.
      --PLANNED: postprocessors may expand to multiple lines? return table
    elseif type(result) == 'string' then
      trace(context, "postprocessed:", context.TEXT, "->", result)
      context.TEXT = result
    elseif result == false then
      trace(context, "preprocessed drop:", context.TEXT)
      context.TEXT = nil
      break
    elseif result == true then
      -- NOP
    else
      warn(context, "postprocessor returned wrong type"..":", active_postprocessors[i], type(result)) --cwarn.<HEXSTRING>: <STRING> ::
      --cwarn.<HEXSTRING>:  Postprocessor returned unsupported type (or nil).
    end
  end

  strsubst_run(context, 'unescape')

end





---------------
-- Operators --
---------------

--op:
--: Operators define how documentation comments are evaluated, they are the core functionality
--: of pipadoc and mandatory in the pipadoc syntax to define a pipadoc comment line. It is
--: possible to (re-)define operators. Operators must be a single punctuation character.
--:
local procfuncs = {}
local genfuncs = {}

--api_op:
--:
--: Operators
--: ^^^^^^^^^
--:
--: Operators have 2 functions associated. The first one is the processing function that
--: defines how a documentation comment gets stored. The second one is the generator function
--: which will emits the documentation at output time.
--:
function operator_register(char, procfunc, genfunc) --: Register a new operator
  --:   char:::
  --:     single punctuation character except '.' defining this operator.
  --:   procfunc +function (context)+:::
  --:     a function which receives a CONTEXT table of the current line.
  --:     The procfunc processes and stores the context in appropriate
  --:     fashion (see <<index_section_append,section_append()>>).
  --:   genfunc +function (context, output)+:::
  --:     a function generating the output from given context, appending
  --:     it to the supplied 'output' table.
  --:
  assert(string.match(char, "^%p$") == char)
  assert(char ~= '.')
  assert_type(procfunc, 'function')
  assert_type(genfunc, 'function')
  dbg(nil, "register operator:", char)
  procfuncs[char] = procfunc
  genfuncs[char] = genfunc
end


local operator_pattern_cache

function operator_pattern()
  if not operator_pattern_cache then
    operator_pattern_cache = "["
    for k in pairs(procfuncs) do
      operator_pattern_cache = operator_pattern_cache..k
    end
    operator_pattern_cache = operator_pattern_cache.."]"
  end
  return operator_pattern_cache
end






--------------------
-- Initialization --
--------------------

-- store state for block comments
local block_section
local block_key

local function filetypes_builtin()
  --filetypes_builtin:scons SCons,
  filetype_register("scons", "^SConstuct$", "#")

  --filetypes_builtin:cmake CMake,
  filetype_register("cmake", {"^CMakeLists.txt$","%.cmake$"}, {"#", "#[["})

  --filetypes_builtin:c C, C++, Headerfiles,
  filetype_register("c", {"%.c$","%.cpp$", "%.C$", "%.cxx$", "%.h$", "%.hpp$", "%.hxx$"},
                    {"//", "/*"})

  --filetypes_builtin:lua Lua,
  filetype_register("lua", {"%.lua$"}, "--")

  --filetypes_builtin:automake Autoconf, Automake,
  filetype_register("automake", {"%.am$", "%.in$", "^configure.ac$"}, {"#", "dnl"})

  --filetypes_builtin:make Makefiles,
  filetype_register("makefile", {"^Makefile$", "%.mk$", "%.make$"}, "#")

  --filetypes_builtin:shell Shell,
  filetype_register("shell", {"%.sh$", "%.pl$", "%.awk$", }, "#")

  --filetypes_builtin:perl Perl,
  filetype_register("perl", {"%.pl$", }, "#")

  --filetypes_builtin:awk AWK,
  filetype_register("awk", {"%.awk$", }, "#")

  --filetypes_builtin:prolog Prolog,
  filetype_register("prolog", {"%.yap$", "%.pro$", "%.P$"}, "%")

  --filetypes_builtin:text Textfiles, Pipadoc (`.pdoc`),
  filetype_register("text", {"%.txt$", "%.TXT$", "%.pdoc$", "^-$"}, {"PIPADOC:", ""})

  --filetypes_builtin:java Java, C#,
  filetype_register("java", {"%.java$", "%.cs$"}, {"//", "/*"})

  --filetypes_builtin:objective_c Objective-C,
  filetype_register("objc", {"%.h$", "%.m$", "%.mm$"}, {"//", "/*"})

  --filetypes_builtin:python Python,
  filetype_register("python", "%.py$", "#")

  --filetypes_builtin:visualbasic Visual Basic,
  filetype_register("visualbasic", "%.vb$", "'")

  --filetypes_builtin:php PHP,
  filetype_register("php", "%.php%d?$", {"#", "//", "/*"})

  --filetypes_builtin:javascript Javascript,
  filetype_register("javascript", "%.js$", "//", "/*")

  --filetypes_builtin:delphi Delphi, Pascal,
  filetype_register("delphi", {"%.p$", "%.pp$", "^%.pas$"}, {"//", "{", "(*"})

  --filetypes_builtin:ruby Ruby,
  filetype_register("ruby", "%.rb$", "#")

  --filetypes_builtin:sql SQL,
  filetype_register("sql", {"%.sql$", "%.SQL$"}, {"#", "--", "/*"})
end


-- nesting level for conditional blocks
local condblock_level = 0

local function setup()
  --PLANNED: os.setlocale by option
  gcontext_set "<setup>"

  request "luarocks.loader"

  do
    local time = os.time()
    local date = os.date("*t", time)
    --GLOBAL:date {VARDEF YEAR, MONTH, DAY, HOUR, MINUTE}
    --GLOBAL:date   Current date information
    GLOBAL.YEAR = date.year
    GLOBAL.MONTH = date.month
    GLOBAL.DAY = date.day
    GLOBAL.HOUR = date.hour
    GLOBAL.MINUTE = date.min

    --PLANNED: locale support for dates
    --GLOBAL:date {VARDEF DAYNAME, MONTHNAME}
    --GLOBAL:date   The name of the day of week or month
    GLOBAL.DAYNAME = os.date("%A", time)
    GLOBAL.MONTHNAME = os.date("%B", time)

    --GLOBAL:date {VARDEF DATE}
    --GLOBAL:date   Current date in YEAR/MONTH/DAY format
    GLOBAL.DATE = date.year.."/"..date.month.."/"..date.day
    --GLOBAL:date {VARDEF LOCALDATE}
    --GLOBAL:date   Current date in current locale format
    GLOBAL.LOCALDATE = os.date("%c", time)
  end

  if not opt_nodefaults then
    --PLANNED: read style file like a config, lower priority, different paths (./ /etc/ ~/ ...)
    --PLANNED: configfile for each markup (pipadoc_asciidoc.lua) etc
    filetypes_builtin()
  end

  --op_builtin:
  --: `:` ::
  --:   The documentation operator. Defines normal documentation text. Each pipadoc comment using
  --:   the `:` operator is processed as documentation. Later when generating the toplevel
  --:   Section is used to paste all other documentation in proper order together.
  --:
  operator_register(
    ":",
    function (context)
      if context.KEY and context.ARG then
        warn(context, "ARG and KEY defined in store operator") --cwarn.<HEXSTRING>: <STRING> ::
        --cwarn.<HEXSTRING>:  The store operators ':' and '+' must either be 'section<op>key' or 'section.key<op>' but not 'section.key<op>key'.
        context.ARG = nil
      end

      if context.ARG then
        context.KEY = context.ARG
        context.ARG = nil
      end

      if context.TEXT ~= "" and (context.SECTION or context.KEY) then
        --oneline
        context.SECTION = context.SECTION or block_section
        strsubst_run(context, 'escape')
        if context.TEXT then
          section_append(context.SECTION, context.KEY, context)
        end
      elseif context.TEXT == "" and (context.SECTION or context.KEY) then
        --block head
        block_section = context.SECTION or block_section
        block_key = context.KEY
        trace(context, "block: ", block_section.."."..(block_key or '-'))
      else
        --block cont
        context.SECTION = context.SECTION or block_section
        context.KEY = context.KEY or block_key
        strsubst_run(context, 'escape')
        if context.TEXT then
          section_append(context.SECTION, context.KEY, context)
        end
      end
    end,

    function (context, output)
      if not condblock_disabled then
        table.insert(output, context)
      end
    end
  )

  --op_builtin:
  --: `+` ::
  --:   Concat operator. Like ':' but appends text at the last line instead creating a new line.
  --:   Note that only the 'TEXT' is appended all other context information gets lost.
  --:
  operator_register(
    "+",
    function (context)
      if context.KEY and context.ARG then
        warn(context, "ARG and KEY defined in store operator")
        context.ARG = nil
      end

      if context.ARG then
        context.KEY = context.ARG
        context.ARG = nil
      end

      if context.TEXT ~= "" and (context.SECTION or context.KEY) then
        --oneline
        context.SECTION = context.SECTION or block_section
        strsubst_run(context, 'escape')
        if context.TEXT then
          section_concat(context.SECTION, context.KEY, context)
        end
      elseif context.TEXT == "" and (context.SECTION or context.KEY) then
        --block head
        block_section = context.SECTION or block_section
        block_key = context.KEY
        trace(context, "block: ", block_section.."."..(block_key or '-'))
      else
        --block cont
        context.SECTION = context.SECTION or block_section
        context.KEY = context.KEY or block_key
        strsubst_run(context, 'escape')
        if context.TEXT then
          section_concat(context.SECTION, context.KEY, context)
        end
      end
    end,

    function (context, output)
      die(nil, "not reached")
    end
  )


  --op_builtin:
  --: `=` ::
  --:   Section paste operator. Takes a section name as argument and will paste that section in
  --:   place.
  --:
  operator_register(
    "=",
    function (context)
      context.SECTION = context.SECTION or block_section

      if context.ARG then
        section_append(context.SECTION, context.KEY or block_key, context)
      else
        warn(context, "paste argument missing")  --cwarn.<HEXSTRING>: <STRING> ::
        --cwarn.<HEXSTRING>:  Using the '=' operator without an argument.
      end
    end,

    function (context, output)
      trace(context, "paste: ", context.ARG)

      if sections[context.ARG] then
        output_paste(sections[context.ARG], output)
      else
        warn(context, "no such section", context.ARG) --cwarn.<HEXSTRING>: <STRING> ::
        ---cwarn.<HEXSTRING>:  The given section is not defined.
      end
    end
  )


  --op_builtin:
  --: ``{` ::
  --:   Conditional block start. Needs a string substitution predicate as ARG and its
  --:   arguments (without the closing curly brace). Evaluated at 'output' times. When this
  --:   predicate evaluates to *true* then the following documentation is included in the
  --:   output, when *false* then the following output within this block is supressed. A
  --:   conditional block must end with the matching closing curly brace operator. Conditional
  --:   blocks can be nested. For possible predicates see <<Predicates,below>>.
  --:
  operator_register(
    "{",
    function (context)
      context.SECTION = context.SECTION or block_section
      if not context.ARG then
        warn(context, "missing predicate") --cwarn.<HEXSTRING>: <STRING> ::
        ---cwarn.<HEXSTRING>:  Conditional block begin needs a predicate.
      end
      section_append(context.SECTION, context.KEY or block_key, context)
    end,

    function (context)
      condblock_level = condblock_level + 1
      if not condblock_disabled and strsubst(context, "{"..context.ARG.." "..context.TEXT.."}") == "" then
        condblock_disabled = condblock_level
      end
      trace(context, "block begin: ", condblock_level, condblock_disabled and "disabled" or "enabled")
    end
  )


  --op_builtin:
  --: ``}` ::
  --:   Conditional output block end. Must match a preceeding block start.
  --{NOT {EQUAL {TOPLEVEL} README}
  --: +
  --: .Example (shell syntax):
  --: ----
  --: #MAIN:
  --: #\{HAVE something
  --: #: something is defined to:
  --: #\{NOT \{DEFINED HIDE_SOMETHING\}
  --: #=something
  --: #\}
  --: #\}
  --: #something: define something here.
  --: ----
  --}
  --:
  operator_register(
    "}",
    function (context)
      context.SECTION = context.SECTION or block_section
      section_append(context.SECTION, context.KEY or block_key, context)
    end,

    function (context, output)
      if condblock_level == 0 then
        warn(context, "mismatched condblock end") --cwarn.<HEXSTRING>: <STRING> ::
        ---cwarn.<HEXSTRING>:  Conditional block end without a begin before.
      else
        trace(context, "block end: ", condblock_level)
        if condblock_disabled and condblock_disabled == condblock_level then
          condblock_disabled = nil
        end
        condblock_level = condblock_level - 1
      end
    end
  )


  local function sortprocess(context)
    context.SECTION = context.SECTION or block_section
    context.KEY = context.KEY or block_key

    if context.ARG then
      section_append(context.SECTION, context.KEY, context)
    else
      warn(context, "sort argument missing") --cwarn.<HEXSTRING>: <STRING> ::
      ---cwarn.<HEXSTRING>:  Using the '@', '$' or '#' operator without an argument.
    end
  end

  function sortgenerate(context, output)
    dbg(context, "sort:", context.OP)
    local section = sections[context.ARG]

    if section and #section.keys == 0 then
      output_sort(section, context.OP, output)
    elseif not condblock_disabled then
      warn(context, "no keys in section", context.ARG) --cwarn.<HEXSTRING>: <STRING> ::
      ---cwarn.<HEXSTRING>:  The given section has no key entries but should be sorted.
    end
  end


  --op_builtin:
  --: `@` ::
  --:   Alphabetic sorting operator. Takes a section name as argument and will paste section
  --:   text alphabetically sorted by its keys.
  --:
  --PLANNED: option for sorting locale
  --PLANNED: option for sorting (up/down)
  operator_register(
    "@",
    sortprocess,
    sortgenerate
  )


  --op_builtin:
  --: `$` ::
  --:   Generic sorting operator. Takes a section name as argument and will paste section text
  --:   sorted by its keys.
  --:
  --PLANNED: option for sorting locale
  --PLANNED: option for sorting (up/down)
  operator_register(
    "$",
    sortprocess,
    sortgenerate
  )


  --op_builtin:
  --: `#` ::
  --:   Numerical sorting operator. Takes a section name as argument and will paste section text
  --:   numerically sorted by its keys.
  --:
  --PLANNED: option for sorting (up/down)
  operator_register(
    "#",
    sortprocess,
    sortgenerate
  )


  --op_builtin:
  --: `!` ::
  --:   Section drop operator. Deletes the section given as argument at output time.
  --:   Used to clean up orphan warnings for unused sections for certain toplevels.
  --:
  operator_register(
    "!",
    function (context)
      context.SECTION = context.SECTION or block_section
      context.KEY = context.KEY or block_key
      section_append(context.SECTION, context.KEY, context)
    end,

    function (context, output)
      dbg(context, "section_drop: ", context.ARG)
      sections[context.ARG] = nil
    end
  )


  -- load config files
  if opt_config_set or not opt_nodefaults then
    gcontext_set "<loadconfig>"

    dbg(nil, "load config:", opt_config)
    local config = loadfile(opt_config)

    if config then
      config()
    else
      local fn = warn
      if opt_config_set then
        fn = die
      end
      fn(nil, "can't load config file"..":", opt_config) --cwarn.<HEXSTRING>: <STRING> ::
      --cwarn.<HEXSTRING>:  The config file ('--config' option) could not be loaded.
    end
  end

  preprocessors_attach()
  postprocessors_attach()
end




----------------------
-- Input Processing --
----------------------

local function line_process(context, comment)
  --context_parsed:
  --:pre {VARDEF PRE}
  --:pre   Contains the source code in font of the line comment.
  --:comment {VARDEF COMMENT}
  --:comment   Character sequence which is used as line comment.
  --:section {VARDEF SECTION}
  --:section   Section where the documentation should appear.
  --:key {VARDEF KEY}
  --:key   Sort key
  --:op {VARDEF OP}
  --:op   Single punctuation operator defining how to process this line.
  --:arg {VARDEF ARG}
  --:arg   Optional argument to the operator. This can be the sort key
  --:arg   (alphabetic or numeric) or another section name for pasting.
  --:text {VARDEF TEXT}
  --:text  The actual Documentation Text.

  -- special case for plain text files
  if comment == "" then
    context.PRE, context.COMMENT, context.SECTION, context.OP, context.KEY, context.ARG, context.TEXT =
      "", " ", nil, ":", nil, nil, context.SOURCE
  else
    local pattern = "^(.-)("..comment..")([%w_]*)%.?([%w_]-)("..operator_pattern()..")([%w_]*)%s?(.-)$"
    context.PRE, context.COMMENT, context.SECTION, context.KEY, context.OP, context.ARG, context.TEXT =
      string.match(context.SOURCE, pattern)
    context.SECTION = maybe_text(context.SECTION)
    context.KEY = maybe_text(context.KEY)
    context.ARG = maybe_text(context.ARG)
  end

  local op = context.OP
  if op then
    dbg(context, "source:", context.SOURCE)
    trace(context,
          "parsed:", context.PRE,
          "section:", context.SECTION,
          "key:", context.KEY,
          "op:", op,
          "arg:", context.ARG,
          "text:", context.TEXT)

    context.SOURCE = nil

    local ok,err = pcall(procfuncs[op], context)
    if not ok then
      warn(context, "operator processing failed"..":", op, err) --cwarn.<HEXSTRING>: <STRING> ::
      --cwarn.<HEXSTRING>:  Error executing a operators processor.
    end

    trace(context,
          "--------------------------------------------------\n")
  end
end


local function file_alias(filename)
  for i=1,#opt_aliases do
    local ok, alias, n = pcall(string.gsub, filename, opt_aliases[i][1], opt_aliases[i][2], 1)
    if ok and n>0 then
      dbg(nil, "alias:", filename, alias)
      return alias
    elseif not ok then
      warn(nil, "alias pattern error"..":", alias, opt_aliases[i][1], opt_aliases[i][2])  --cwarn.<HEXSTRING>: <STRING> ::
      --cwarn.<HEXSTRING>:  The pattern for a file alias is invalid.
    end
  end
  return filename
end

--api_various:
function context_new(parent, new) --: Create a new context.
  --: Used whenever preprocessors/macros need to generate new local scope.
  --:   parent:::
  --:     The parent context to extend from.
  --:   new:::
  --:     A table (or nil) containing the additional members for the
  --:     new context.
  assert_type(parent, 'table')
  maybe_type(new, 'table')
  return setmetatable(new or {}, {__index = parent})
end

local function file_process(file)
  -- filecontext is a partial context storing data
  -- of the current file processed

  local filecontext = context_new(GLOBAL, {
                                     FILE="<file_process>",
  })

  local fh
  if file == '-' then
    filecontext.FILE = "<stdin>"
    fh = io.stdin
  else
    fh = io.open(file)

    if not fh then
      warn(filecontext, "file not found"..":", file) --cwarn.<HEXSTRING>: <STRING> ::
      --cwarn.<HEXSTRING>:  A given file can not be opened (wrong path or typo?).
      return
    end
    filecontext.FILE = file
  end

  local filetype = filetype_get(file_alias(file))

  if not filetype then
    warn(filecontext, "unknown file type"..":", file) --cwarn.<HEXSTRING>: <STRING> ::
    --cwarn.<HEXSTRING>:  The type of the given file was not recognized (see <<_usage,'--register'>> option).
    return
  end

  --context_file:
  --:file {VARDEF COMMENTS_TABLE}
  --:file   A Lua table with the all possible line comment character sequences
  --:file   for this filetype. Available at preprocessing time before parsing.
  filecontext.COMMENTS_TABLE = filetype.comments

  block_section = filecontext.FILE:match("[^./]+%f[.%z]")
  dbg(filecontext, "section:", block_section)

  --context_file:
  --:language {VARDEF LANGUAGE}
  --:language   The language name of this file.
  filecontext.LANGUAGE = filetype.language
  dbg(filecontext, "language:", filecontext.LANGUAGE)


  local lineno = 0
  for line in fh:lines() do
    lineno = lineno + 1

    --context_preprocess:
    --:source {VARDEF SOURCE}
    --:source   The line as read from the input file.
    local context = context_new(filecontext, {
                                  LINE = lineno,
                                  SOURCE = line,
    })


    preprocessors_run(filetype.preprocessors, context)

    if context.SOURCE then
      local comment = comment_select(context.SOURCE, filetype)

      if comment then
        line_process(context, comment)
      end
    end
  end
  fh:close()
end

local function inputs_process()
  gcontext_set "<inputs_process>"

  local processed_files = {}
  for _, filename in ipairs(opt_inputs) do
    if processed_files[filename] then
      warn(nil, "input file given twice"..":", filename) --cwarn.<HEXSTRING>: <STRING> ::
      --cwarn.<HEXSTRING>:  Ignored a file given multiple times for input.
    else
      file_process(filename)
      processed_files[filename] = true
    end
  end
end




-----------------------
-- Output Processing --
-----------------------

local sofar_rec={}

function output_paste(section, output)
  assert_type(section, 'table')
  assert_type(output, 'table')


  if sofar_rec[section] then
    warn(nil, "recursive paste"..":", which) --cwarn.<HEXSTRING>: <STRING> ::
    --cwarn.<HEXSTRING>:  Pasted sections (see <<_built_in_operators,paste operator>>) can not recursively
    --cwarn.<HEXSTRING>:  include themself.
    return
  end

  if #section == 0 then
    warn(nil, "section is empty"..":", which) --cwarn.<HEXSTRING>: <STRING> ::
    --cwarn.<HEXSTRING>:  Tried to paste ('=') an empty section.
    return
  end

  sofar_rec[section] = true
  section.usecnt = (section.usecnt or 0) + 1

  for i=1,#section do
    GLOBAL.LINE=i
    local genfunc = genfuncs[section[i].OP]
    if genfunc then
      local ok, err = pcall(genfunc, section[i], output)
      if not ok then
        warn(section[i], "generator failed"..":", err) --cwarn.<HEXSTRING>: <STRING> ::
        --cwarn.<HEXSTRING>:  Error in operators generator function.
      end
    else
      warn(nil, "no generator function for:", section[i].OP)
    end
  end
  sofar_rec[section] = nil
end

function output_sort(section, op, output)
  assert_type(section, 'table')
  assert_type(section.keys, 'table')
  assert_char(op)
  assert(string.find("@#$", op, 1, true), "No such sort operator")
  maybe_type(output, 'table')
  dbg(nil, "output_sort:", section.name)

  --PLANNED:A refuse to sort on input phase
  --PLANNED: rule based / table for sort operators, opchar = \{filter, compare\}

  section.sorted = section.sorted or {}
  local sorted = section.sorted[op]

  if not sorted then
    sorted = {}
    section.sorted[op] = sorted

    -- filter out what to sort
    for k in pairs(section.keys) do
      if op == '@' and not tonumber(k) then
        table.insert(sorted, k)
      elseif op == '#' and tonumber(k) then
        table.insert(sorted, k)
      elseif op == '$' then
        table.insert(sorted, k)
      end
    end

    if #sorted == 0 then
      warn(context, "sorted section is empty"..":",which) --cwarn.<HEXSTRING>: <STRING> ::
      --cwarn.<HEXSTRING>:  Trying to sort a section by keys yield zero results.
      return
    end

    -- sort it
    if op == '@' or op == '$' then
      table.sort(sorted, function(a,b) return tostring(a) < tostring(b) end)
    elseif op == '#' then
      table.sort(sorted, function(a,b) return(tonumber(a) or 0) <(tonumber(b) or 0) end)
    end
  end

  if output then
    for i=1,#sorted do
      output_paste(section.keys[sorted[i]], output)
    end
  end

  return #sorted
end

function orphan_doublet_report()
  local orphan = {FILE = "<orphan>"}
  local doublete = {FILE = "<doublete>"}

  for name, section in pairs(sections) do
    if #section > 0 then
      if not section.usecnt then
        warn(orphan, "section unused"..":", name) --cwarn.<HEXSTRING>: <STRING> ::
        --cwarn.<HEXSTRING>:  The printed section was not used. When this is intentional this
        --cwarn.<HEXSTRING>:  messages can be supressed by dropping the unused section with
        --cwarn.<HEXSTRING>:  the '!' operator.
      elseif section.usecnt > 1 then
        warn(doublete, "section multiple times used"..":", name, section.usecnt) --cwarn.<HEXSTRING>: <STRING> ::
        --cwarn.<HEXSTRING>:  Section was used multiple times in the output.
      end
    end

    for kname, key in pairs(section.keys) do
      if not key.usecnt then
        warn(orphan, "section key unused"..":", name.."."..kname) --cwarn.<HEXSTRING>: <STRING> ::
        --cwarn.<HEXSTRING>:  Section with keys (numeric or alphabetic) was not used.
      elseif key.usecnt > 1 then
        warn(doublete, "section key multiple times used"..":", name.."."..kname, key.usecnt) --cwarn.<HEXSTRING>: <STRING> ::
        --cwarn.<HEXSTRING>:  Section was used multiple times in the output (sorting operators).
      end
    end
  end
end





----------
-- Main --
----------

do
  args_parse(arg)
  setup()
  inputs_process()

  if opt_list_sections then
    for _,s in ipairs(section_list()) do
      io.stdout:write(s)
      io.stdout:write('\n')
    end
  end

  if opt_dryrun then
    os.exit(0)
  end

  collectgarbage()

  local output = {}

  gcontext_set "<output>"
  strsubst_language_init (GLOBAL)

  local topsection = sections[GLOBAL.TOPLEVEL.."_"..GLOBAL.MARKUP] or sections[GLOBAL.TOPLEVEL]
  if topsection then
    output_paste(topsection, output)
  else
    die (nil, "toplevel section undefined"..":", GLOBAL.TOPLEVEL) --cwarn.<HEXSTRING>: <STRING> ::
    --cwarn.<HEXSTRING>:  The section used as root for the output generation is not defined.
  end

  local outfd, err = io.stdout

  if opt_output then
    outfd, err = io.open(opt_output, "w+")

    if not outfd then
      die(nil, "failed to open"..":", opt_output, err) --cwarn.<HEXSTRING>: <STRING> ::
      --cwarn.<HEXSTRING>:  Output file could not be opened.
    end
  end


  gcontext_set "<postprocessing>"
  section_append = function () die(nil, "section_append() not available when postprocessing") end
  section_concat = function () die(nil, "section_concat() not available when postprocessing") end


  for i=1,#output do
    postprocessors_run(output[i])
    if output[i].TEXT then
      outfd:write(output[i].TEXT)
      outfd:write(GLOBAL.NL)
    end
  end
  -- free memory
  output = nil
  collectgarbage()

  if opt_output then
    outfd:close()
  end

  orphan_doublet_report()
end






-------------------
-- Documentation --
-------------------


--MAIN_asciidoc:
--=MAIN
--=INDEX
--!ISSUES
--!MAIN_text
--!README_text
--!PLANNED
--!TODO
--!WIP
--!FIXME
--!DONE

--MAIN_text:
--=MAIN
--!INDEX
--!ISSUES
--!MAIN_asciidoc
--!README_text
--!PLANNED
--!TODO
--!WIP
--!FIXME
--!DONE

--README_text:
--=MAIN
--!INDEX
--!ISSUES
--!MAIN_asciidoc
--!MAIN_text
--!PLANNED
--!TODO
--!WIP
--!FIXME
--!DONE




--MAIN:
--: pipadoc - Documentation extractor
--: =================================
--: :author:   Christian Thaeter
--: :email:    ct@pipapo.org
--: :date:     {DAY}. {MONTHNAME} {YEAR}
--{EQUAL {MAYBE FLAVOR} asciidoctor
-- asciidoctor needs a hacks for escaping
--: :du: __
--: :uDATE: DATE
--}
--:
--:
--: [preface]
--: Introduction
--: ------------
--:
--: Embedding documentation in program source files often results in the problem that the
--: structure of a program is not the optimal structure for the associated documentation.
--: Still there are many good reasons to maintain documentation together with the source right
--: within the code which defines the documented functionality. Pipadoc addresses this problem
--: by extracting special comments out of a source file and let one define rules how to compile
--: the documentation into proper order.  This is somewhat similar to ``literate Programming''
--: but it puts the emphasis back to the code.
--:
--: Pipadoc is programming language and documentation system agnostic, all it requires is that
--: the programming language has some form of comments starting with a defined character sequence
--: and spanning to the end of the source line. Moreover documentation parts can be written in
--: plain text files aside from the sources.
--:
--:
--: History
--: -------
--:
--: This 'pipadoc' implemented in Lua follows an earlier implementation with a slightly different
--: (incompatible) syntax and less features which was implemented in AWK. Updating to the new
--: syntax should be straightforward and is suggested for any projects using pipadoc.
--:
--:
--: Getting the Source
--: ------------------
--:
--: Pipadoc is managed the git revision control system. You can clone the repository with
--:
--:  git clone --depth 1 git://git.pipapo.org/pipadoc
--:
--: The 'master' branch will stay stable and development will be done on the 'devel' branch.
--:
--:
--: Installation
--: ------------
--:
--: Pipadoc is single Lua source file `pipadoc.lua` which is portable among most Lua versions
--: (PUC Lua 5.1, 5.2, 5.3, 5.4, Luajit, Ravi). It ships with a `pipadoc.install` shell script
--: which figures a suitable Lua version out and installs `pipadoc.lua` as `pipadoc` in a
--: given directory (the current directory by default).
--:
--: There are different ways how this can be used in a project:
--:
--: - When a installed Lua version is known from the build tool chain one can include the
--:   `pipadoc.lua` into the project and call it with the known Lua interpreter.
--: - One can rely on a pipadoc installed in '$PATH' and just call that from the build tool chain
--: - One could ship the `pipadoc.lua` and `pipadoc.install` and do a local install in the build
--:   directory and use this pipadoc thereafter.
--:
--:
--: Usage
--: -----
--:
--: Pipadoc is called with options and all input files. It may read a configuration file. When
--: generating output it is either send to _stdout_ or saved as a given output file.
--:
--: NOORIGIN
--: .....
--=usage
--: .....
--: ORIGIN
--:
--:
--: Basic concepts
--: --------------
--:
--: Pipadoc is controlled by special line comments. This is chosen because it is the most common
--: denominator between almost all programming languages. To make a line comment recognized as
--: pipadoc comment it needs to be followed immediately by a operator sequence. Which in the
--: simplest case is just a single punctuation character.
--:
--: These comments are stored to named documentation sections. One of the main concepts of pipadoc
--: is that one can define which and in what order these sections appear in the final output.
--:
--: To add special functionality and extend the semantics one can define pre and post processors.
--: Preprocessors are defined per input programming language and process all source lines. They can
--: modify the source arbitrary before pipadoc does the parsing. This allows to generate completely
--: new content. Lift parts on the source code side over to the documentation and generate
--: additional information such as indices and glossaries.
--: Postprocessors are defined for output markup and process every line in output order. The allow
--: to augment output in a markup specific way.
--:
--: There is a string substitution/template engine which can processes text. The string
--: substitution engine also implements a small lisp-like programming language which can be used
--: to generate content programmatically.
--:
--:
--{NOT {EQUAL {TOPLEVEL} README}
--: Example
--: ~~~~~~~
--:
--: Without further ado, here is an example showing pipadoc documentation on a shell script.
--: For a more complex example one could look at 'pipadoc.lua' itself. The exact pipadoc
--: syntax is described in the next section.
--:
--: .An example document (example.sh)
--: ----
--: #!/bin/sh
--: #: here the default section is 'example', derived from 'example.sh'
--: #oneline:o this is appended to the section 'oneline' under key 'o'
--: #: back to the 'example' section
--: #newname:
--: #: this starts a new section block named 'newname'
--: #oneline:a this is appended to the section 'oneline' under key 'a'
--: #MAIN:
--: #: Assemble the document
--: #: first the 'newname'
--: #=newname
--: #: then 'example'
--: #=example
--: #: and finally 'oneline' alphabetically sorted by keys
--: #@oneline
--: ----
--:
--: processed by pipadoc
--: ....
--: lua pipadoc.lua -- example.sh
--: ....
--:
--: Will result in
--: ----
--: Assemble the document
--: first the 'newname'
--: this starts a new section block named 'newname'
--: then 'example'
--: here the default section is 'example', derived from 'example.sh'
--: back to the 'example' section
--: and finally 'oneline' alphabetically sorted by keys
--: this is appended to the section 'oneline' under key 'a'
--: this is appended to the section 'oneline' under key 'o'
--: ----
--:
--:
--}
--: Syntax
--: ------
--:
--: .In short:
--: A pipadoc comment is any 'line-comment' of the programming language directly (without spaces)
--: followed by a optional alphanumeric section name which may have a sorting key appended by
--: a dot, followed by an operator, followed by an optional argument. Possibly followed by the
--: documentation text itself.
--:
--: Only lines qualify this syntax are processed as pipadoc documentation. Preprocessors run
--: before the parsing is done and may translate otherwise non pipadoc sourcecode into documentation.
--:
--: .The formal syntax looks like:
--: ....
--: <pipadoc> ::= [source] <linecomment> <opspec> [ <space> [documentationtext]]
--:
--: <source> ::= <any source code text>
--:
--: <linecomment> ::= <the filetypes linecomment sequence>
--:
--: <opspec> ::= [section['.'key]] <operator> [argument]
--:
--: <section> ::= <alphanumeric text including underscore>
--:
--: <operator> ::= ":" | "+" | "=" | "\{" | "\}" | "@" | "$" | "#" | "!"
--:                | <user defined operators>
--:
--: <key> ::= <alphanumeric text including underscore>
--:
--: <argument> ::= <alphanumeric text including underscore>
--:
--: <documentationtext> ::= <rest of the line>
--: ....
--:
--{NOT {EQUAL {TOPLEVEL} README}
--: IMPORTANT: Pipadoc does not know anything except the line comment characters about the source
--:            programming languages syntax. This includes literal strings and any other
--:            syntactic form which may look like a line comment, but is not. Such lines need to
--:            be dropped by a preprocessor to make them unambiguous.
--:            There config shipped with pipadoc gives an example to drop a line when it end with
--:           "NODOC".
--:
--: Documentation can be either in blocks or single lines.
--:
--: Block::
--:   Start with a documentation comment including a section or argument specifier but are not
--:   followed by documentation text on the same line.
--:   The text block then follows in documentation comments where section and
--:   argument are empty. Blocks span until a new documentation block is started.
--: One Line::
--:   Is defined by a documentation comment which sets section and/or argument followed by
--:   documentation text on the same line. They can be interleaved within blocks.
--:   This is used to define index and glossary items right within block documentation.
--:
--}
--:
--: Sections and Keys
--: -----------------
--:
--=sections
--:
--:
--: Order of operations
--: -------------------
--:
--: Pipadoc reads all files line by line. and processes them in the following order:
--:
--: Preprocessing ::
--:   Preprocessors are Lua functions who may alter the entire content of a line before any
--:   further processing. They get a 'context' table passed in with the 'SOURCE' member
--:   containing the line read from the input file.
--:
--: Parsing ::
--:   The line is broken down into its components and the operators processing function
--:   will be called. The ':' and '+' operators do a first string substitution pass to
--:   expand variables. This string substitution is done in input order.
--:   String substitution macros may leverage this for additional state and may generate
--:   extra content like indices and append that to the respective sections.
--:
--: Output Ordering ::
--:   The output order is generated by assembling the '{BRACED toplevel}_{BRACED markup}' or
--:   if that does not exist the '{BRACED toplevel}' section.
--:   The paste and sorting operators there define the section order of the document.
--:   The conditional operators '\{' and '\}' are also evaluated at this stage and may omit some
--:   blocks depending on selection predicates.
--:
--: Postprocessing ::
--:   For each output context the postprocessors run in output order.
--:   Finally a last string substitution pass is applied in output order.
--:   This pass can generate markup specific changes.
--:
--: Writeout ::
--:   The finished document is written to the output.
--:
--: Report empty sections, Orphans and Doubletes::
--:   Pipadoc keeps stats on how each section was used. Finally it gives a report (as warning)
--:   on sections which appear to be unused or used more than once. These warnings may be ok, but
--:   sometimes they give useful hints about typing errors. To suppress such reports of
--:   intentional left out sections one can use the '!' operator.
--:
--: It is important to know that reading happens only line by line, operations can not span
--: lines. While Processing steps can be stateful and thus preserve information for further
--: processing.
--:
--:
--: Filetypes
--: ---------
--:
--=filetypes
--:
--{NOT {EQUAL {TOPLEVEL} README}
--: .Predefined Filetypes:
--@filetypes_builtin
--:
--}
--:
--: Markup Languages
--: ----------------
--:
--: The core of pipadoc is completely agnostic about the markup used within the documentation
--: strings. The '--markup' option only sets the 'MARKUP' variable and output generation tries
--: include the markup in the toplevel. Usually only string substitution and postprocessors
--: should handle markup related things.
--:
--: The shipped configuration file comes with postprocessors for 'asciidoc' and 'text'
--: markups. More will will be added in future (org-mode, markdown).
--:
--:
--: Operators
--: ---------
--:
--=op
--:
--=op_builtin
--:
--:
--: Processors
--: ----------
--:
--: Pre- and Post- processors are lua functions that allow to manipulate text
--: programmatically. They get the full context of the current processed line as input and can
--: return the modified line or choose to drop or keep the line. They are can freely store
--: some state elsewhere and thus allow some processing that spans lines which is normally not
--: available in pipadoc.
--:
--:
--: Preprocessors
--: ~~~~~~~~~~~~~
--:
--: Preprocessors are per filetypes. A preprocessor can modify any input line
--: prior it gets parsed and further processed. Preprocessors are used to autogenerate
--: extra documentation comments from code. Lifting parts of the code to the documentation
--: side. They operate on the whole source line, not only the pipadoc comment.
--:
--: This is the place to generate data for new sections (Gloassaries, Indices).
--:
--: Postprocessors
--: ~~~~~~~~~~~~~~
--:
--: Postprocessors run at output generation time. They are registered per markup type.
--: They are used to augment the generated output with markup specific things. They operate
--: only on parsed documentation comments and only those should be modified. All other data is
--: already available and stored, thus they may not generate new sections.
--:
--:
--: String Substitution Engine
--: --------------------------
--:
--: Documentation text is be passed to the string substitution engine which recursively
--: substitutes macros within curly braces. The substitutions are taken from the passed
--: context (and GLOBAL's).
--:
--: When a docline is entirely a single string substitution (starting and ending with a
--: curly brace) and the string substitution resulting in an empty string, then the
--: whole line becomes dopped. If this is not intended one could add a second empty
--: '{BRACED NIL}' FOO string substitution to the line.
--:
--{NOT {EQUAL {TOPLEVEL} README}
--: .Simple String Substitution Example:
--: ----
--: The date is \{DATE\}
--: \{Undefined\}
--: \{NIL\}
--: \{NIL\}\{NIL\}
--: ----
--:
--: {IF {EQUAL {FLAVOR} asciidoctor}
--+  {THEN . +{BRACED \{uDATE\}}+}
--+  {ELSE . +{BRACED DATE}+}
--+ } gets replaced with the current date.
--: . +{BRACED Undefined}+ will stay literally.
--: . +{BRACED NIL}+ will remove the entire line.
--: . +{BRACED NIL}{BRACED NIL}+ will result in an empty line.
--:
--: String substitutions names consist of alphanumeric characters or underlines.
--: These names themself can be composed from string substitutions (see example below).
--: It may be followed with a delimiting character (space) and an optional argument string.
--: This argument string gets passed to functions or recursive string substitutions. Names
--: starting and ending with 2 underscores are reserved to the implementation.
--:
--: NOTE: That undefined macros stay literal allows for partial evaluation. The string
--:       substitution language uses this and becomes only defined/active after the
--:       preprocessing. The +{BRACED MAYBE}+ macro can supress this and +{BRACED LITERAL}+
--:       can be used to delay evaluation.
--:
--}
--: A string substitution can be either a string or a Lua function which shall return
--: the substituted text.
--:
--: * When the susbtitution is defined as string, then the argument passed as +__ARG__+ and the
--:   resulting string will become recursively evaluated by the engine.
--: * When it is a function, then this function is responsible for calling recursive evaluation
--:   on its arguments and results.
--:
--{NOT {EQUAL {TOPLEVEL} README}
--: Curly braces, can be escaped with backslashes or backtick characters. These characters can
--: be escaped by themself. This escaping works by replacing the respective characters with
--: reserved macros first and finally after all other processing is done move these back to
--: their literal characters. This macros can be used when defining macros that contain some
--: of this special characters.
--:
--: .The reserved macros are:
-- asciidoc and asciidoctor are incompatible in escaping syntax
--: {GLOBAL RESERVED_MACRO {IF {EQUAL {FLAVOR} asciidoctor}
--+  {THEN +\{\{du\}{__ARG__}\{du\}\}+ ::}
--+  {ELSE +\\\{\_\_{__ARG__}__\}+ ::}}
--+ }
--: {RESERVED_MACRO BACKSLASH}
--:   The backslash character: +{__BACKSLASH__}+
--:
--: {RESERVED_MACRO BACKTICK}
--:   The backtick character: +{__BACKTICK__}+
--:
--: {RESERVED_MACRO BRACEOPEN}
--:   The opening curly brace: +{__BRACEOPEN__}+
--:
--: {RESERVED_MACRO BRACECLOSE}
--:   The closing curly brace: +{__BRACECLOSE__}+
--:
--: .More elaborate String Substitution Example
--: -----
--: GLOBAL.SIMPLE = "a simple example"
--: GLOBAL.BRACED = "\{BRACED_\{MARKUP\} \{__ARG__\}\}"
--: GLOBAL.BRACED_text = "\{__BRACEOPEN__\}\{__ARG__\}\{__BRACECLOSE__\}"
--: GLOBAL.BRACED_asciidoc = "\{__BACKSLASH__\}\{__BRACEOPEN__\}\{__ARG__\}\{__BRACECLOSE__\}"
--: -----
--:
--: .Explanation:
--: . '{BRACED SIMPLE}' will expand to 'a simple example'
--: . In 'BRACED_{BRACED MARKUP}', '{BRACED MARKUP}' becomes replaced with the defined markup
--:   language to use.
--: . The argument get passed along with '{BRACED +++__ARG__+++}'.
--: . The resulting string from 2. dispatches on the markup language to one of the following.
--: . 'BRACED_text' defines how the braces are rendered around '+++__ARG__+++' in text markup.
--: . 'BRACED_asciidoc' does the same for asciidoc output.
--:
--: NOTE: The escaping rules become a bit complicated because one has to consider the escaping
--:       rules of all components involved. This is first Lua when assigned in literal strings.
--:       Second the escaping rules of the string substitution engine itself (curly braces,
--:       backslashes and backticks). Possibly the escaping rules of the source language wher
--:       the documentation is hosted and finally the escaping rules of the targeted markup
--:       language.
--:
--}
--:
--: String Substitution Language
--: ----------------------------
--:
--: The string substitution engine comes with some macros predefined which implement a simple
--: lisp-like programming language to allow conditional evaluation and (in future) other useful
--: features. This language is enabled when assembling the output in order and evaluated in
--: the last step of the postprocessor.
--:
--:
--{NOT {EQUAL {TOPLEVEL} README}
--: Syntax
--: ~~~~~~
--:
--: The string substitution engine supports only a simple syntax with a macro name and one
--: single argument. The string substitution language extends that by parsing the argument in
--: following ways:
--:
--: Normal Form::
--: Elements are single words separated by spaces and/or arbitary text (including spaces)
--: written  within curly braces.
--: * Single words are left unchaged as given
--: * Separating spaces are removed
--: * Text within curly braces becomes recursively evaluted with 'strsubst()'
--: * When this evaluation result is completely within curly braces (no substitution done)
--:   these braces are removed
--:
--: Special Form::
--: Use argument as single text not parsed into multiple arguments. It may become recursively
--: evaluated or not, depending on the actual macro implementation.
--:
--: .Example
--: ----
--: \{AND \{DEFINE something\} \{NOT \{DEFINED something_else\} \{BOOL \{anotherthing\}\}\}\}
--: ----
--: * Results in *true* when 'something' is defined and 'something_else' is not defined and
--:   'anotherthing' is not an empty string.
--:
--: Conventions
--: ^^^^^^^^^^^
--:
--: Pipadoc defines only all-upppercase names for macros some special used names are withing
--: double underscores. These should not be used in user-defined programs. Moreover the string
--: substitution language will only allow to define new names that don't shadow existing names
--: and limits mutation to local scopes only.
--:
--:
--: Predefined Macros
--: ~~~~~~~~~~~~~~~~~
--:
--=strsubst_lang
--:
--:
--}
--: Configuration File
--: ------------------
--:
--: Pipadocs main objective is to scrape documentation comments from a project and generate
--: output in desired order. Such an basic approach would be insufficient for many common cases.
--: Thus pipadoc has pre and postprocessors and the string substitution engine to generate and
--: modify documentation in an extensible way. These are defined in an user supplied
--: configuration file.
--:
--: Pipadoc tries to load the configuration file on startup. By default it is named
--: +pipadoc_config.lua+ in the current directory. This name can be changed with the
--: '--config' option.
--:
--: The configuration file is used to define pre- and post- processors, define states
--: for those, define custom operators and string substitution macros. It is loaded and
--: executed as it own chunk and may only access the global variables and call the
--: API functions described below.
--:
--: Without a configuration file none of these processors are defined any only few
--: variables for string substitution engine are set.
--:
--:
--{NOT {EQUAL {TOPLEVEL} README}
--: Shipped Configuration File
--: ~~~~~~~~~~~~~~~~~~~~~~~~~~
--:
--: Pipadoc comes with a configuration file for generating it's own documentation and
--: assist the test suite. This is a good starting point for writing your own configuration.
--:
--: This configuration file implements the features explained next.
--:
--: Preprocessors
--: ^^^^^^^^^^^^^
--:
--=shipped_config_pre
--:
--: Postprocessors
--: ^^^^^^^^^^^^^^
--:
--=shipped_config_post
--:
--: String Substitutions Macros
--: ^^^^^^^^^^^^^^^^^^^^^^^^^^^
--:
--=shipped_config_subst
--:
--:
--}
--: External Libraries
--: ~~~~~~~~~~~~~~~~~~
--:
--: 'pipadoc' does not depend on any external Lua libraries. Nevertheless modules can be loaded
--: optionally to augment the behavior and provide extra features. Plugin-writers should
--: use the 'request()' function instead the Lua 'require()', falling back to simpler but usable
--: functionality when some library is not available or call 'die()' when a reasonable fallback
--: won't do it.
--:
--: Pipadoc already calls 'request "luarocks.loader"' to make rocks modules available.
--:
--:
--{NOT {EQUAL {TOPLEVEL} README}
--: Programming API for Extensions
--: ------------------------------
--:
--:
--: [[GLOBAL]]
--: Documentation Variables
--: ~~~~~~~~~~~~~~~~~~~~~~~
--:
--: The 'GLOBAL' Lua table holds key/value pairs of variables and macros
--: with global definitions. These are used by the core, processors and string substitution.
--: Simple string assignments can be set from the command line. Configuration files may define
--: more complex Lua functions for string substitutions.
--:
--:
--: [[CONTEXT]]
--: The Context
--: ~~~~~~~~~~~
--:
--: Processors, operators, string substitution calls and diagnostics get a context
--: passed along. This context represents the parsed line plus
--: everything that's defined at file level and in GLOBAL.
--:
--: In a few cases a fake-context with FILE name in angle brackets is passed around for
--: diagnostic functions.
--:
--:
--: Predefined Variables and Context Members
--: ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
--:
--: .The 'GLOBAL' context contains:
--@GLOBAL
--:
--: .A file level context contains:
--@context_file
--:
--: .At preprocessing time the context contains:
--@context_preprocess
--:
--: .After lines are parsed each line context contains:
--@context_parsed
--:
--: Additional global members may be defined by command line options or the string
--: substitution language.
--:
--: String substitution creates local contexts for each level of evaluation which may define
--: local members.
--:
--:
--: Exported Functions
--: ~~~~~~~~~~~~~~~~~~
--:
--: pipadoc exports global functions for the use in pre/post processors from config files.
--:
--=api_load
--=api_logging
--=api_typecheck
--=api_typeconv
--=api_strsubst
--=api_strsubst_lang
--=api_filetypes
--=api_op
--=api_preproc
--=api_postproc
--=api_sections
--:
--: Other Functions
--: ~~~~~~~~~~~~~~~
--:
--=api_various
--:
--:
--}
--{NOT {EQUAL {TOPLEVEL} README}
--: [appendix]
--: Common Errors and Warnings
--: --------------------------
--:
--: Pipadoc emits warnings on problems. Even with warnings processing will usually go on but
--: the output may need some attention. This section explains these warnings and errors and shows
--: possible ways to fix them.
--: Warnings are suppressed with the '--quiet' option.
--:
--$cwarn
--:
--}
--{NOT {EQUAL {TOPLEVEL} README}
--: [appendix]
--: Generate the Pipadoc Documentation
--: ----------------------------------
--:
--: 'pipadoc' documents itself with embedded asciidoc text. This can be extracted with
--:
--: ----
--: lua pipadoc.lua -m asciidoc pipadoc.lua pipadoc_config.lua -o pipadoc.txt
--: ----
--:
--: The resulting `pipadoc.txt` can then be processed with the asciidoc tool chain to produce
--: distribution formats:
--:
--: ----
--: # generate HTML
--: asciidoc -a toc pipadoc.txt
--:
--: # generate PDF
--: a2x -L -k -v --dblatex-opts "-P latex.output.revhistory=0" pipadoc.txt
--: ----
--:
--: For convenience there is a +--make-doc+ option. This generates the 'README' and 'pipadoc.html'.
--: When called with +-D PDF --make-doc+ the 'pipadoc.pdf' is generated as well.
--: 'FLAVOR' can be set to 'asciidoc' or 'asciidoctor' to select an asciidoc variant. If not
--: given this is autodetected and defaults to asciidoctor.
--PLANNED: section for common control variables like PDF FLAVOR ...
--:
--:
--: [appendix]
--: Issue Tracking
--: --------------
--:
--: Issues in pipadoc are tracked in source code comments as well. The included configuration
--: file implement some preprocessors and macros for that.
--:
--: The '--issues' option which generates 'pipadoc_issues.txt' and 'pipadoc_issues.html' with
--: extensive git annotations about at what time an commit an issue was edited.
--:
--: There is a '-eissues' option which generates simpler text only list on stdout without the
--: git annotations. The output can directly be used by emacs (and possible other editors) to
--: jump to the source code in question.
--:
--:
--}
--: [appendix]
--: GNU General Public License
--: --------------------------
--:
--: NOORIGIN
--: ----
--=license
--: ----
--: ORIGIN
--:
--{NOT {EQUAL {TOPLEVEL} README}
--: License Explanation
--: ~~~~~~~~~~~~~~~~~~~
--:
--: The License (GPLv3) only applies to pipadoc and any derivative work. The purpose of pipadoc
--: is to extract documentation from other files, this does not imply that these source files
--: from which the documentation is extracted need to be licensed under the GPL, neither does
--: this imply that the extracted documentation need to be licensed under the GPL.
--:
--: The GPL applies when you distribute pipadoc itself, in original or modified form. Since
--: pipadoc is written in the Lua scripting language, you already distribute its source as well,
--: which naturally makes this distribution conform with the GPL.
--:
--: Nevertheless, when you make any improvements to pipadoc please consider to contact
--: Christian Thäter <ct@pipapo.org> for including them into the mainline.
--:
--}
--INDEX:
--: [index]
--: Index
--: -----
--:
--$INDEX
--:
--:

--PLANNED: DOCME, example section about one source can be used to generate different docs
--PLANNED: TEXT on special ops become parameters  --$WIP optional, reverse ....


--ISSUES:
--: ISSUES
--: ------
--:
--{HAVENOT $WIP $FIXME $TODO $PLANNED $DONE
--: No open issues.
--}
--{HAVE $WIP
--: .WIP
--:
--$WIP
--:
--:
--}
--{HAVE $FIXME
--: .FIXME
--:
--$FIXME
--:
--:
--}
--{HAVE $TODO
--: .TODO
--:
--$TODO
--:
--:
--}
--{HAVE $PLANNED
--: .PLANNED
--:
--$PLANNED
--:
--:
--}
--{HAVE $DONE
--: .DONE
--:
--$DONE
--:
--:
--}
--!GLOBAL
--!INDEX
--!MAIN
--!MAIN_asciidoc
--!MAIN_text
--!api_filetypes
--!api_load
--!api_logging
--!api_op
--!api_postproc
--!api_preproc
--!api_sections
--!api_strsubst
--!api_strsubst_example
--!api_strsubst_lang
--!api_typecheck
--!api_typeconv
--!api_various
--!context
--!cwarn
--!filetypes
--!filetypes_builtin
--!license
--!op
--!op_builtin
--!sections
--!strsubst_lang
--!shipped_config_post
--!shipped_config_pre
--!shipped_config_subst
--!usage

--PLANNED: named processors, define processing chains or sort by priority
--PLANNED: not only pipadoc.conf but also pipadoc.sty templates, conf are local only configurations, .sty are global styles
--TODO: strsubst on SECTION, KEY and ARG //{BRACED SECTION\}.{BRACED KEY\}:{BRACED ARG\}
--PLANNED: how to enable strsubst-lang at start w/o problems for the postprocessing evaluation?
--PLANNED: INIT section for configuration
--PLANNED: test expected stderr in test suite
--PLANNED: DOCME documentation is usually only for one markup designed, dispatch on strsubst make only maintaining easier
--PLANNED: CONFIG:PRE
--PLANNED: CONFIG:POST
--PLANNED: CONFIG:GENERATE
--PLANNED: manpage

--- Local Variables:
--- mode: lua
--- compile-command: "lua pipadoc.lua --eissues"
--- End:
