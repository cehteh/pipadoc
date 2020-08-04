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
--PLANNED: compose/concat operator .. hint: delayed section_append/strsubst
--PLANNED: Version check for documents \{VERSION 2\} ...
--PLANNED: --disable-strsubst option .. NOSTRSUBST STRSUBST macros
--PLANNED: merge sections for sorting --#foo+bar+baz or something like this


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
}

GLOBAL_POST = {}

local gcontext = setmetatable (
  {
    --context:file {VARDEF FILE}
    --context:file   The file or section name currently processed or some special annotation
    --context:file   in angle brackets (eg '<startup>') on other processing phases
    --context:line {VARDEF LINE}
    --context:line   Current line number of input or section, or indexing key
    --context:line   Lines start at 1
    FILE = "<startup>"
  }, {__index = GLOBAL})

local args_done = false
local opt_verbose = 1
local opt_nodefaults = false
local opt_toplevel = "MAIN"
local opt_aliases = {}
local opt_inputs = {}
local opt_output = nil
--PLANNED: make opt_config a list
local opt_config = "pipadoc_config.lua"
local opt_config_set = false






--------------------------------
-- Type Checks and Conversion --
--------------------------------

--api_typecheck:
--:
--: Type Checks
--: ^^^^^^^^^^^
--:
--: Wrappers around 'assert' to check externally supplied data. On success 'var' will be returned
--: otherwise an assertion error is raised.
--:

function assert_type(var, expected) --: checks that the 'var' is of type 'expected'
  assert(type(var) == expected, "type error: "..expected.." expected, got "..type(var))
  return var
end

function maybe_type(var, expected) --: checks that the 'var' is of type 'expected' or nil
  assert(var == nil or type(var) == expected, "type error: "..expected.." or nil expected, got "..type(var).. " >>>"..tostring(var).."<<<")
  return var
end

function assert_char(var) --: checks that 'var' is a single character
  assert(type(var) == "string" and #var == 1, "type error: single character expected")
  return var
end

function assert_notnil(var) --: checks that 'var' is not 'nil'
  assert(type(var) ~= "nil", "Value expected")
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
  v = tostring (v)
  if v ~= "" then
    return v
  else
    return nil
  end
end






----------------------
-- Helper Functions --
----------------------

local function check_args(arg, n)
  assert(#arg >= n, "missing arg: "..arg[n-1])
end

local function set_gcontext(file, line)
  assert_type(file, 'string')
  gcontext.FILE = file
  gcontext.LINE = line
end

--api_various:
function pattern_escape (s)  --: Escape all characters in string 's' so that it cane be used as verbatim pattern.
  return (s:gsub("%W", "%%%1"))
end






--------------------------------
-- Error handling and logging --
--------------------------------

--PLANNED: log to PIPADOC_LOG section, later hooked in here
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
  maybe_type (context, 'table')
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
function dump_table(context, p,t)
  for k,v in pairs(t) do
    dbg(context, p,k,v)
    if type(v) == 'table' then
      dump_table(context, p.."/"..k, v)
    end
  end
end






----------------------------
-- Commandline Processing --
----------------------------

--api_various:
function add_inputfile(filename) --: Add a 'filename' to the list of files to process
  assert_type(filename, "string")
  opt_inputs[#opt_inputs+1] = filename
end

--PLANNED: rename alias_register
function register_alias(from, to) --: Register a new alias
  assert_type(from, "string")
  assert_type(to, "string")
  dbg(nil, "register alias:", from, "->", to)
  opt_aliases[#opt_aliases+1] = {from, to}
end

function usage()
  for i=1,#options do
    print(options[i])
  end
  os.exit(0)
end

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
    check_args(arg, i+3)
    filetype_register(arg[i+1], arg[i+2], arg[i+3])
    return 3
  end,
  "", --:  <STRING>


  "    -t, --toplevel <name>", --:  <STRING>
  "                        sets 'name' as toplevel node [MAIN]", --:  <STRING>
  ["-t"] = "--toplevel",
  ["--toplevel"] = function (arg, i)
    check_args(arg, i+1)
    opt_toplevel = arg[i+1]
    dbg(nil, "toplevel:", opt_toplevel)
    return 1
  end,
  "", --:  <STRING>

  "    -c, --config <name>", --:  <STRING>
  "                        selects a config file [pipadoc_config.lua]", --:  <STRING>
  ["-c"] = "--config",
  ["--config"] = function (arg, i)
    check_args(arg, i+1)
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
    dbg("nodefaults")
  end,
  "", --:  <STRING>


  "    -m, --markup <name>", --:  <STRING>
  "                        selects the markup engine for the output [text]", --:  <STRING>
  ["-m"] = "--markup",
  ["--markup"] = function (arg, i)
    check_args(arg, i+1)
    GLOBAL.MARKUP = arg[i+1]
    dbg(nil, "markup:", GLOBAL.MARKUP)
    return 1
  end,
  "", --:  <STRING>


  "    -o, --output <file>", --:  <STRING>
  "                        writes output to 'file' [stdout]", --:  <STRING>
  ["-o"] = "--output",
  ["--output"] = function (arg, i)
    check_args(arg, i+1)
    opt_output = arg[i+1]
    dbg(nil, "output:", opt_output)
    return 1
  end,
  "", --:  <STRING>

  "    -a, --alias <pattern> <as>", --:  <STRING>
  "                        aliases filenames to another filetype.", --:  <STRING>
  "                        force example, treat .install files as shell files:", --:  <STRING>
  "                         --alias '(.*)%.install' '%1.sh'", --:  <STRING>
  ["-a"] = "--alias",
  ["--alias"] = function (arg, i)
    check_args(arg, i+2)
    register_alias (arg[i+1], arg[i+2])
    return 2
  end,
  "", --:  <STRING>

  "    -D, --define <name>[=<value>]", --:  <STRING>
  "                        define a GLOBAL variable to value or 'true'", --:  <STRING>
  "    -D, --define -<name>", --:  <STRING>
  "                        undefine a GLOBAL variable", --:  <STRING>
  ["-D"] = "--define",
  ["--define"] = function (arg,i)
    check_args(arg, i+1)
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

  "    -P, --define-post <name>[=<value>]", --:  <STRING>
  "                        define a GLOBAL_POST variable to value or 'true'", --:  <STRING>
  "    -P, --define-post -<name>", --:  <STRING>
  "                        undefine a GLOBAL_POST variable", --:  <STRING>
  ["-P"] = "--define-post",
  ["--define-post"] = function (arg,i)
    check_args(arg, i+1)
    local key,has_value,value = arg[i+1]:match("^([%w_]+)(=?)(.*)")
    local undef = arg[i+1]:match("^[-]([%w_]+)")
    if undef then
      dbg(nil, "undef_post:", undef)
      GLOBAL_POST[undef] = nil
    elseif key then
      if has_value == "" then
        value = 'true'
      end
      dbg(nil, "define_post:", key, value)
      GLOBAL_POST[key] = value
    end
    return 1
  end,
  "", --:  <STRING>

  -- intentionally here undocumented, only works in development tree
  ["--make-doc"] = function (arg, i)
    os.execute [[
        lua pipadoc.lua -m text pipadoc.lua pipadoc_config.lua -o README
        lua pipadoc.lua -m asciidoc pipadoc.lua pipadoc_config.lua -o pipadoc.txt
        if test ! -e  pipadoc.html -o pipadoc.txt -nt pipadoc.html; then
          asciidoc -a toc pipadoc.txt
        fi
        if test ! -e  pipadoc.pdf -o pipadoc.txt -nt pipadoc.pdf; then
          a2x -L -k -v --dblatex-opts "-P latex.output.revhistory=0" pipadoc.txt
        fi
    ]]
  end,

  ["--issues"] = function (arg, i)
    --PLANNED: run universally
    os.execute [[
        lua pipadoc.lua -m asciidoc -D GIT -D ISSUES -t ISSUES pipadoc.lua pipadoc_config.lua
    ]]
  end,

  "    --", --:  <STRING>
  "                        stops parsing the options and treats each", --:  <STRING>
  "                        following argument as input file", --:  <STRING>
  ["--"] = function () args_done=true end,

  --PLANNED: --list-filetypes
  --PLANNED: --list-sections
  --PLANNED: eat (double, triple, ..) empty lines (do this in a postprocessor)
  --PLANNED: add debug report (warnings/errors) to generated document PIPADOC_LOG section
  --PLANNED: wrap at blank/intelligent -> postprocessor
  --PLANNED: wordwrap
  --PLANNED: source indent with pretty printing --indent columns

  "", --:  <STRING>
  "  inputs are file names or a '-' that indicates standard input", --:  <STRING>
}

function parse_args(arg)
  set_gcontext "<parse_args>"

  local i = 1
  while i <= #arg do
    gcontext.LINE=i
    while string.match(arg[i], "^%-%a%a+") do
      parse_args {"-"..string.sub(arg[i],2,2)}
      arg[i] = "-"..string.sub(arg[i],3)
    end

    if not options[arg[i]] then
      add_inputfile(arg[i])
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
    warn(nil, "can't load module:", name) --cwarn: <STRING> ::
    --cwarn:  'request()' failed to load a module.
    return nil
  end
end
--:






--------------
-- Strsubst --
--------------

--api_strsubst:
--:
--: String Substitution
--: ^^^^^^^^^^^^^^^^^^^
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

local function table_inverse (t)
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
function strsubst (context, str, escape) --: substitute text
  --:   context:::
  --:     The current context which defines all variables and
  --:     macros for the substitution.
  --:   str:::
  --:     The string to operate on
  --:   escape:::
  --:     Rule for special character escaping
  --:     true:::: handle escaping in one pass
  --:     'escape':::: 1st pass
  --:     'unescape':::: 2nd pass
  --:     nil:::: no special escaping
  trace (context, "strsubst:", str)
  maybe_type (context, "table")
  assert_type (str, "string")

  context = context or gcontext
  local sofar = {}

  local function strsubst_intern (str)
    trace(context, "strsubst_intern:", str)

    return str:gsub("%b{}",
                    function (capture)
                      local ret = capture
                      local subst = false

                      local var,arg = capture:match("^{(%a[%w_{}]*).?(.*)}$")
                      if not var then return capture end
                      var = strsubst_intern (var)

                      -- recursively dereference names when braced
                      do
                        local sofar = {}
                        while not sofar[var] and type(context[var]) == "string" and context[var]:match("^(%b{})$") do
                          subst = true
                          sofar[var] = true
                          var = strsubst_intern (context[var]:sub(2,-2))
                        end
                      end
                      if context[var] then
                        subst = true
                        var = context[var]
                      end

                      arg = strsubst_intern (arg)

                      if subst then
                        if not sofar[var] then
                          sofar[var] = true
                          if type(var) == 'function' then
                            local ok, result = pcall(var, context, arg)
                            if ok then
                              ret = tostring(result)
                            else
                              warn (context, "strsubst function failed:", var, result) --cwarn: <STRING> ::
                              --cwarn:  strsubst tried to call a custom function which failed.
                            end
                          else
                            ret = tostring(var)..arg
                          end
                        ret = strsubst_intern(ret)
                          sofar[var] = nil
                        else
                          warn (context, "strsubst recursive expansion:", var)  --cwarn: <STRING> ::
                          --cwarn:  cyclic substitution.
                        end
                      else
                        if escape == 'unescape' and not ret:match "^{__.*__}$" then
                          warn (context, "strsubst no expansion:", capture)  --cwarn: <STRING> ::
                          --cwarn:  no substitution defined.
                        end
                      end

                      return ret
                    end
    )
  end

  if escape == true or escape == 'escape' then
    str =  str:gsub("[`\\]([{}\\])", strsubst_escapes)
  end

  str = strsubst_intern(str)

  if escape == true or escape == 'unescape'then
    str = str:gsub("%b{}", strsubst_escapes_back)
  end

  trace (context, "strsubst done:", str)
  return str
end






----------------------
-- Section handling --
----------------------

--sections:
--: Text in pipadoc is appended to named 'sections'. Text can be associated with some
--: alphanumeric key under that section. This enables later sorting for indices and glossaries.
--:
--: Sections can be one line or span a block of lines.
--:
--: One-line sections are defined when a section and maybe a key is followed by documentation
--: text. Block sections start with the section definition but no documentation text on the same
--: line. A block stays active until the next block section definition. One-line doctext can be
--: interleaved into Blocks.
--:
--: The default block section name is the files name up, but excluding to the first dot.
--:
--: Sections are later brought into the desired order by pasting them into a 'toplevel' section.
--: This default name for the 'toplevel' section is 'MAIN_\{markup\}' or if that does not exist
--: just 'MAIN'.
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
--: lua pipadoc.lua example.sh
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
--: The pipadoc documentation you are just reading here is made and embedded in 'pipadoc.lua'
--: itself using 'asciidoc' as markup. Refer to the source itself to see how it is done.
--:
local sections = {}
local sections_usecnt = {}
local sections_keys_usecnt = {}

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
  if key and #key > 0 then
    sections[section].keys[key] = sections[section].keys[key] or {}
    table.insert(sections[section].keys[key], context)
  else
    table.insert(sections[section], context)
  end
end






---------------
-- Filetypes --
---------------

--filetypes:
--: Pipadoc needs to know about the syntax of line comments of the files it is reading.
--: For this patterns are registered to be matched against the file name together with a
--: list of line comment characters.
--:
--: Definitions for a lot common programming languages are already included. For languages
--: that support block comments the opening (but not the closing) commenting characters are
--: registered as well. This allows one to define section blocks right away. But using the
--: comment closing sequence right on the line will clobber the output, don't do that!
--:
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
--: for plain text documentation files. Which also uses the "PIPADOC:" keyword to enable special
--: operations within text files.
--:
--: New uncommon filetypes can be added from a config file with 'filetype_register()'  or with
--: the '--register' command-line option.
--:
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
  --: filetype_register("C", \{"%.c$","%.cpp$","%.C$", "%.cxx$", "%.h$"\}, \{"//", "/*"\})
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

local function comment_select (line, filetype)
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
--PLANNED: add a mnemonic name preprocessor_register (name, langpat, preprocess)
function preprocessor_register (langpat, preprocess) --: register a preprocessor
  --:   langpat:::
  --:     Register preprocessor to all filetypes whose mnemonic matches 'langpat'.
  --:   preprocess:::
  --:     The preprocessor to register. Can be one of:
  --:     `function (context) ... end` ::::
  --:       Takes the context of the current source line and shall return:
  --:       *  the preprocessed line
  --:       *  false to drop the line
  --:       *  true to keep the line unaltered
  --:       Preprocessors may store state or have other side effect using API functions.
  --:     +\{pattern, repl [, n]\}+ ::::
  --:       Generates a function calling 'context.SOURCE:gsub(pattern, repl [, n])' for preprocessing.
  --:
  --PLANNED: langpat as list of patterns
  assert_type (langpat, "string")
  dbg (nil, "register preprocessor:", langpat, preprocess)

  if type (preprocess) == "table" then
    local params = preprocess
    preprocess = function (context)
      local result = context.SOURCE:gsub (params[1], params[2], params[3])
      if result == context.SOURCE then
        return true
      end
      return result
    end
  end

  if type (preprocess) == "function" then
    table.insert(preprocessors, {pattern=langpat, preprocessor=preprocess})
  else
    warn (nil, "unsupported preprocessor type") --cwarn: <STRING> ::
    --cwarn:  Tried to 'preprocessor_register()' something that is not a function or table.
  end
end

-- internal, hook preprocessors into the filetype descriptors
local function preprocessors_attach ()
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
          trace (nil, "add preprocessor for:", k, ppdesc.preprocessor)
          table.insert(filetype_preprocessors, ppdesc.preprocessor)
          v.preprocessors = filetype_preprocessors
        end
      end
    end
  end
end


local function preprocessors_run (preprocessors, context)
  if preprocessors then
    for i=1,#preprocessors do
      local ok,result = pcall(preprocessors[i], context)
      if not ok then
        warn(context, "preprocessor failed:", result) --cwarn: <STRING> ::
        --cwarn:  preprocessor function error.
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
        warn(context, "preprocessor returned wrong type:", preprocessors[i], type(result)) --cwarn: <STRING> ::
        --cwarn:  preprocessor returned unsupported type (or nil).
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
--PLANNED: add a mnemonic name postprocessor_register (name, markuppat, preprocess)
function postprocessor_register (markuppat, postprocess) --: register a postprocessor
  --:   markuppat:::
  --:     Register postprocessor to all markups whose name matches 'markuppat'.
  --:   postprocess:::
  --:     The postprocessor to register. Can be one of:
  --:     `function (context) ... end` ::::
  --:       Takes the context of the current source line and shall return:
  --:       *  the postprocessed line (context.TEXT)
  --:       *  false to drop the line
  --:       *  true to keep the line unaltered
  --:       Postprocessors may store state or have other side effect using API functions.
  --:     +\{pattern, repl [, n]\}+ ::::
  --:       Generates a function calling 'context.TEXT:gsub(pattern, repl [, n])' for postprocessing.
  --:
  --PLANNED: markuppat as list of patterns
  assert_type (markuppat, "string")
  dbg (nil, "register postprocessor:", markuppat, postprocess)


  if type (postprocess) == "table" then
    local params = postprocess
    postprocess = function (context)
      local result = context.TEXT:gsub (params[1], params[2], params[3])
      if result == context.TEXT then
        return true
      end
      return result
    end
  end

  if type (postprocess) == "function" then
    table.insert(postprocessors, {pattern=markuppat, postprocessor=postprocess})
  else
    warn (nil, "unsupported postprocessor type") --cwarn: <STRING> ::
    --cwarn:  Tried to 'postprocessor_register()' something that is not a function or table.
  end
end


local active_postprocessors = {}

local function postprocessors_attach ()
  for i=1,#postprocessors do
    local ppdesc = postprocessors[i]
    if GLOBAL.MARKUP:match(ppdesc.pattern) then
      trace (nil, "add postprocessor for:", GLOBAL.MARKUP, ppdesc.postprocessor)
      table.insert(active_postprocessors, ppdesc.postprocessor)
    end
  end
end

--PLANNNED: wrap pcall for debugging purpose
local function postprocessors_run (context)
  for i=1,#active_postprocessors do
    local ok, result = pcall(active_postprocessors[i], context)
    if not ok then
      warn(context, "postprocessor failed:", result) --cwarn: <STRING> ::
      --cwarn:  postprocessor function error.
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
      warn(context, "postprocessor returned wrong type:", active_postprocessors[i], type(result)) --cwarn: <STRING> ::
      --cwarn:  postprocessor returned unsupported type (or nil).
    end
  end

  if context.TEXT then
    context.TEXT = strsubst(context, context.TEXT, 'unescape')
  end

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
--: Operators have 2 functions associated. The first one is the processing function which
--: defines how a documentation comment gets stored. The second one is the generator function
--: which will emits the documentation.
--:
function operator_register(char, procfunc, genfunc) --: Register a new operator
  --:   char:::
  --:     single punctuation character except '.' defining this operator.
  --:   procfunc +function(context)+:::
  --:     a function which receives a CONTEXT table of the current line.
  --:     The procfunc processes and store the context in appropriate
  --:     fashion.
   --:   genfunc +function(context)+:::
  --:     a function generating the (sequential) output from given context.
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
    operator_pattern_cache= "["
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


local function builtin_filetypes()
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


local function setup()
  --PLANNED: os.setlocale by option
  set_gcontext "<setup>"

  request "luarocks.loader"

  do
    local time = os.time()
    local date = os.date ("*t", time)
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
    GLOBAL.DAYNAME = os.date ("%A", time)
    GLOBAL.MONTHNAME = os.date ("%B", time)

    --GLOBAL:date {VARDEF DATE}
    --GLOBAL:date   Current date in YEAR/MONTH/DAY format
    GLOBAL.DATE = date.year.."/"..date.month.."/"..date.day
    --GLOBAL:date {VARDEF LOCALDATE}
    --GLOBAL:date   Current date in current locale format
    GLOBAL.LOCALDATE = os.date ("%c", time)
  end

  if not opt_nodefaults then
    --PLANNED: read style file like a config, lower priority, different paths (./ /etc/ ~/ ...)
    --PLANNED: for each language/markup (pipadoc_asciidoc.lua) etc
    builtin_filetypes()
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
        warn (context, "ARG and KEY defined in operator ':', using KEY only") --cwarn: <STRING> ::
        --cwarn:  Operator ':' must either be 'section:key' or 'section.key:' but not 'section.key:key'.
        context.ARG = nil
      end

      if context.ARG then
        context.KEY = context.ARG
        context.ARG = nil
      end

      if context.TEXT ~= "" and (context.SECTION or context.KEY) then
        --oneline
        context.SECTION = context.SECTION or block_section
        context.TEXT = strsubst(context, context.TEXT, 'escape')
        section_append(context.SECTION, context.KEY, context)
      elseif context.TEXT == "" and (context.SECTION or context.KEY) then
        --block head
        block_section = context.SECTION or block_section
        block_key = context.KEY
        trace (context, "block: ", block_section.."."..(block_key or '-'))
      else
        --block cont
        context.SECTION = context.SECTION or block_section
        context.KEY = context.KEY or block_key
        context.TEXT = strsubst(context, context.TEXT, 'escape')
        section_append(context.SECTION, context.KEY, context)
      end
    end,

    function (context, output)
      --PLANNED: link prev/next context
      table.insert(output, context)
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

      if context.ARG and #context.ARG > 0 then
        section_append(context.SECTION, nil, context)
      else
        warn(context, "paste argument missing")  --cwarn: <STRING> ::
        --cwarn:  Using the '=' operator without an argument.
      end
    end,

    function (context, output)
      return output_generate(context.ARG, nil, output)
    end
  )

  local function sortprocess(context)
    context.SECTION = context.SECTION or block_section  --FIXME: move to parser
    context.KEY = context.KEY or block_key  --FIXME: move to parser

    if context.ARG then
      section_append(context.SECTION,  context.KEY, context)
    else
      warn(context, "sort argument missing") --cwarn: <STRING> ::
      ---cwarn:  Using the '@', '$' or '#' operator without an argument.
    end
  end

  local function sortgenerate(context, output)
    dbg(context, "generate_output_sorted")
    local which = context.ARG
    local section = sections[which] and sections[which].keys
    local text = ""

    if section ~= nil then
      sections_keys_usecnt[which] = (sections_keys_usecnt[which] or 0) + 1

      local sorted = {}

      for k in pairs(section) do
        if context.OP == '@' and not tonumber (k) then
          table.insert(sorted, k)
        elseif context.OP == '#' and tonumber (k) then
          table.insert(sorted, k)
        elseif context.OP == '$' then
          table.insert(sorted, k)
        end
      end

      if context.OP == '@' or context.OP == '$' then
        table.sort(sorted, function(a,b) return tostring(a) < tostring(b) end)
      elseif context.OP == '#' then
        table.sort(sorted, function(a,b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
      end

      if #sorted == 0 then
        warn(context, "section is empty:",which) --cwarn: <STRING> ::
        --cwarn:  Using '=', '@' or '#' on a section which has no data (under respective keys).
        return ""
      end

      for i=1,#sorted do
        for j=1,#section[sorted[i]] do
          table.insert(output, section[sorted[i]][j])
        end
      end
    else
      warn(context, "no section named:", which) --cwarn: <STRING> ::
      --cwarn:  Using '=', '@' or '#' on a section which as never defined.
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
  --:   Generic Sorting operator. Takes a section name as argument and will paste section text
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

  if opt_config_set or not opt_nodefaults then
    set_gcontext "<loadconfig>"

    dbg (nil, "load config:", opt_config)
    local config = loadfile(opt_config)

    if config then
      config ()
    else
      local fn = warn
      if opt_config_set then
        fn = die
      end
      fn (nil, "can't load config file:", opt_config) --cwarn: <STRING> ::
      --cwarn:  The config file ('--config' option) could not be loaded.
    end
  end

  preprocessors_attach ()
  postprocessors_attach ()
end




----------------------
-- Input Processing --
----------------------

local function process_line (context, comment)
  --context:
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

  --FIXME: handle oneline/block here

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
      warn (context, "operator processing failed:", op, err) --cwarn: <STRING> ::
      --cwarn:  error executing a operators processor.
    end
    trace(context,
        "--------------------------------------------------\n")
  end
end


local function file_alias(filename)
  for i=1,#opt_aliases do
    local ok, alias, n = pcall(string.gsub, filename, opt_aliases[i][1], opt_aliases[i][2], 1)
    if ok and n>0 then
      dbg (nil, "alias:", filename, alias)
      return alias
    elseif not ok then
      warn (nil, "alias pattern error:", alias, opt_aliases[i][1], opt_aliases[i][2])
    end
  end
  return filename
end

--api_various:
function make_context(parent, new) --: Create a new context.
  --: Used whenever preprocessors/macros need to generate new content.
  --:   parent:::
  --:     The parent context to extend from.
  --:   new:::
  --:     A table (or nil) containing the additional members for the
  --:     new context.
  assert_type (parent, 'table')
  maybe_type (new, 'table')
  return setmetatable(new or {}, {__index = parent})
end



local function process_file(file)
  -- filecontext is a partial context storing data
  -- of the current file processed

  local filecontext = make_context(GLOBAL, {
                                     FILE="<process_file>",
  })

  local fh
  if file == '-' then
    filecontext.FILE = "<stdin>"
    fh = io.stdin
  else
    fh = io.open(file)

    if not fh then
      warn(filecontext, "file not found:", file) --cwarn: <STRING> ::
      --cwarn:  A given File can not be opened (wrong path or typo?).
      return
    end
    filecontext.FILE = file
  end

  local filetype = filetype_get (file_alias(file))

  if not filetype then
    warn(filecontext, "unknown file type:", file) --cwarn: <STRING> ::
    --cwarn:  The type of the given file was not recognized (see <<_usage,'--register'>> option).
    return
  end

  --context:
  --:file {VARDEF COMMENTS_TABLE}
  --:file   A Lua table with the all possible line comment character sequences
  --:file   for this filetype. Already available at preprocessing time.
  filecontext.COMMENTS_TABLE = filetype.comments

  block_section = filecontext.FILE:match("[^./]+%f[.%z]")
  dbg(filecontext, "section:", block_section)

  --context:
  --:language {VARDEF LANGUAGE}
  --:language   The language name of this file.
  filecontext.LANGUAGE = filetype.language
  dbg(filecontext, "language:", filecontext.LANGUAGE)


  local lineno = 0
  for line in fh:lines() do
    lineno = lineno + 1

    --context:
    --:source {VARDEF SOURCE}
    --:source   The line read from the input file, used for preprocessing and will be erased
    --:source   afterward preprocessing is done.
    local context = make_context(filecontext, {
                                   LINE = lineno,
                                   SOURCE = line,
    })


    preprocessors_run (filetype.preprocessors, context)

    if context.SOURCE then
      local comment = comment_select(context.SOURCE, filetype)

      if comment then
        process_line(context, comment)
      end
    end
  end
  fh:close()
end


local function process_inputs()
  set_gcontext "<process_inputs>"

  local processed_files = {}
  for _, filename in ipairs(opt_inputs) do
    if processed_files[filename] then
      warn(nil, "input file given twice:", filename)
    else
      process_file(filename)
      processed_files[filename] = true
    end
  end
end




-----------------------
-- Output Processing --
-----------------------

local sofar_rec={}

function output_generate(which, key, output)
  assert_type(which, 'string')
  maybe_type(key, 'string')
  assert_type(output, 'table')
  set_gcontext "<output>"
  dbg(nil, "generate_output:", which, key)

  local which_key = which
  if key then
    which_key = which_key .. '.' .. key
  else
    key = ""
  end

  local section = sections[which][key] or sections[which]


  if section ~= nil then
    if sofar_rec[which_key] then
      warn(nil, "recursive paste:", which_key) --cwarn: <STRING> ::
      --cwarn:  Pasted sections (see <<_built_in_operators,paste operator>>) can not recursively
      --cwarn:  include themself.
      return ""
    end

    if #section == 0 then
      warn(nil, "section is empty:", which_key)
      return
    end
    sofar_rec[which_key] = true
    sections_usecnt[which_key] = (sections_usecnt[which_key] or 0) + 1

    for i=1,#section do
      GLOBAL.LINE=i
      local genfunc = genfuncs[section[i].OP]
      if genfunc then
        local ok, err = pcall(genfunc, section[i], output)
        if not ok then
          warn(section[i], "generator failed:", err) --cwarn: <STRING> ::
          --cwarn:  error in operators generator function.
        end
      else
        warn(nil, "no generator function for:", section[i].OP)
      end
    end
    sofar_rec[which_key] = nil
  else
    warn(nil, "no section named:", which_key)
  end
end


--PLANNED: some way to hint the checker to suppress these warnings ignore operator --!name
function report_orphan_doubletes()
  local orphan = {FILE = "<orphan>"}
  local doublete = {FILE = "<doublete>"}
  for k,v in pairs(sections_usecnt) do
    if v == 0 then
      warn(orphan, "section unused:", k) --cwarn: <STRING> ::
      --cwarn:  The printed section was not used. This might be intentional when generating
      --cwarn:  only partial outputs.
    elseif v > 1 then
      warn(doublete, "section multiple times used:", k, v) --cwarn: <STRING> ::
      --cwarn:  Section was pasted multiple times in the output.
    end
  end

  for k,v in pairs(sections_keys_usecnt) do
    if v == 0 then
      warn(orphan, "section w/ keys unused:", k) --cwarn: <STRING> ::
      --cwarn:  Section with keys (numeric or alphabetic) was not used.
    elseif v > 1 then
      warn(doublete, "section w/ keys multiple times used:", k, v) --cwarn: <STRING> ::
      --cwarn:  Section was used multiple times in the output ('@', '$' or '#' operator).
    end
  end
end





----------
-- Main --
----------

do
  parse_args(arg)
  setup()
  process_inputs()

  collectgarbage()

  local output = {}

  local topsection = opt_toplevel  --TODO: DOCME
  if sections[opt_toplevel.."_"..GLOBAL.MARKUP] then
    topsection = opt_toplevel.."_"..GLOBAL.MARKUP
  end

  set_gcontext "<output>"
  output_generate(topsection, nil, output)

  local outfd, err = io.stdout

  if opt_output then
    outfd, err = io.open(opt_output, "w+")

    if not outfd then
      die (nil, "failed to open:", err)
    end
  end


  set_gcontext "<postprocessing>"
  section_append = function () die(nil, "section_append() not available when postprocessing") end

  --activate GLOBAL_POST for postprocessing
  setmetatable (GLOBAL, {__index = GLOBAL_POST})

  for i=1,#output do
    postprocessors_run(output[i])
    if output[i].TEXT then
      outfd:write(output[i].TEXT)
      outfd:write(GLOBAL.NL)
    end
  end
  -- free memory
  sections = nil
  output = nil
  collectgarbage()

  if opt_output then
    outfd:close()
  end

  report_orphan_doubletes()
end






-------------------
-- Documentation --
-------------------


--MAIN_asciidoc=MAIN
--MAIN_asciidoc=INDEX

--MAIN_text=MAIN

--MAIN:
--: pipadoc - Documentation extractor
--: =================================
--: :author:   Christian Thaeter
--: :email:    ct@pipapo.org
--: :date:     {DAY}. {MONTHNAME} {YEAR}
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
--: (PUC Lua 5.1, 5.2, 5.3, Luajit, Ravi). It ships with a `pipadoc.install` shell script which
--: figures a  suitable Lua version out and installs `pipadoc.lua` as `pipadoc` in a given
--: directory or the current directory by default.
--:
--: There are different ways how this can be used in a project:
--:
--: - One can rely on a pipadoc installed in $PATH and just call that from the build tool chain
--: - When a installed Lua version is known from the build tool chain one can include the
--:   `pipadoc.lua` into the project and call it with the known Lua interpreter.
--: - One can ship the `pipadoc.lua` and `pipadoc.install` and do a local install in the build
--:   directory and use this pipadoc thereafter
--:
--:
--: Usage
--: -----
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
--: denominator between almost all programming languages.
--:
--: To make a line comment recognized as pipadoc comment it needs to be followed immediately
--: by a operator sequence. Which in the simplest case is just a single punctuation character.
--: One can give a section name left of the operator and an argument/key right of the operator.
--:
--: To add special functionality and extend the semantics one can define pre and post processors.
--:
--: Preprocessors are defined per programming language and process all source lines.
--:
--: Postprocessors are defined per output markup and process every line to be outputed.
--:
--: Finally there is a string substitution/template engine which processes text in curly braces.
--:
--: Syntax
--: ~~~~~~
--:
--: Any 'line-comment' of the programming language directly (without spaces) followed by a
--: optional alphanumeric section name, followed by an operator, followed by an optional
--: argument. Only lines qualify this syntax are processed as pipadoc documentation.
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
--: <operator> ::= ":" | "=" | "@" | "$" | "#" | <user defined operators>
--:
--: <key> ::= <alphanumeric text including underscore>
--:
--: <argument> ::= <alphanumeric text including underscore>
--:
--: <documentationtext> ::= <rest of the line>
--: ....
--:
--: IMPORTANT: Pipadoc does not know anything except the line comment characters about the source
--:            programming languages syntax. This includes literal strings and any other
--:            syntactic form which may look like a line comment, but is not. Such lines need to
--:            be dropped by a preprocessor to make them unambiguous.
--:
--: There config shipped with pipadoc gives an example to drop a line when it end with "NODOC".
--:
--: ----
--: const char* example = "//MAIN: this is a C string and not documentation"; //NODOC{NIL}
--: ----
--:
--: Documentation can be either blocked or oneline.
--:
--: Block::
--:   Start with a documentation comment including a section or argument specifier but are not
--:   followed by documentation text on the same line.
--:   The text block then follows in documentation comments where section and
--:   argument are empty. Blocks span until a new documentation block is started.
--: Oneline::
--:   Is defined by a documentation comment which sets section and/or argument followed by
--:   documentation text on the same line. They can be interleaved within blocks.
--:   This is used to define index and glossary items right within block documentation.
--:
--:
--: Order of operations
--: ~~~~~~~~~~~~~~~~~~~
--:
--: Pipadoc reads all files line by line. and processes them in the following order:
--:
--: Preprocessing ::
--:   Preprocessors are Lua functions who may alter the entire content of a line before any
--:   further processing. They get a 'context' passed in with the 'SOURCE' member containing
--:   the line read from the input file.
--:
--: Parsing ::
--:   The line is broken down into it's components and the operators processing function
--:   will be called which is responsible for storing. The colon (':') operator also does a first
--:   string substitution pass to expand variables. This strsubst is done in input order.
--:   Macros may leverage this for additional state and may generate extra content like indices
--:   and append that to the respective sections.
--:
--: Output Ordering ::
--:   The output order is generated by assembling the '\{toplevel\}_\{markup\}' or if that does
--:   not exist the '\{toplevel\}' section.
--:   The paste and sorting operators on the toplevel and included sections define the
--:   order of the document.
--:
--: Postprocessing ::
--:   For each output context the postprocessors run in output order.
--:   A final string substitution pass is applied in 'output' order then.
--:
--: Writeout ::
--:   The finished document is written to the output.
--:
--: Report empty sections, Orphans and Doubletes::
--:   Pipadoc keeps stats on how each section was used. Finally it gives a report (as warning)
--:   on sections which appear to be unused or used more than once. These warnings may be ok, but
--:   sometimes they give useful hints about typing errors.
--:
--: It is important to know that reading happens only line by line, operations can not span
--: lines. The processing steps may be stateful and thus preserve information for further
--: processing.
--:
--:
--: Sections and Keys
--: -----------------
--:
--=sections
--:
--: Filetypes
--: ---------
--:
--=filetypes
--:
--: Programming languages supported by pipadoc
--: ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
--:
--@filetypes_builtin
--:
--:
--: Operators
--: ---------
--:
--: Operators define what is considered as pipadoc comment and how to assemble the resulting document.
--:
--=op_builtin
--:
--:
--: Configuration File
--: ------------------
--:
--: Pipadoc tries to load a configuration file on startup. By default it's named
--: +pipadoc_config.lua+ in the current directory. This name can be changed by the '--config'
--: option.
--:
--: The configuration file is used to define pre- and post- processors, define states
--: for those, define custom operators and string substitution macros. It is loaded and
--: executed as it own chunk and may only access the global variables (GLOBAL, CONTEXT) and
--: API functions described below.
--:
--: Preprocessors
--: ~~~~~~~~~~~~~
--:
--: One can register multiple preprocessors for filetypes. A preprocessor can modify any
--: line prior it is parsed and further processed. By default pipadoc has no preprocessors
--: defined. The user may define these in a config file.
--:
--: Preprocessors are used to autogenerate documentation comments from code. Lifting
--: parts of the code to the documentation side.
--:
--: Postprocessors
--: ~~~~~~~~~~~~~~
--:
--: Postprocessors run at output generation time. They are registered per markup types.
--: Processors are called in order of their definition.
--:
--: They are used to augment the generated output with markup specific things.
--:
--: String Substitutions
--: ~~~~~~~~~~~~~~~~~~~~
--:
--: Documentation text is be passed to the string substitution engine which recursively
--: substitutes expressions within curly braces. The substitutions are taken from the passed
--: context (and GLOBAL's). Strings are replaced, functions become evaluated, everything else is
--: translated with Luas 'tostring()' function.
--:
--: The names for substitutions must start with an alphabetic character or underline and can
--: be followed by alphanumeric characters or underlines. It may be followed with a delimiting
--: character (space) and an optional argument string which gets passed to functions or
--: retained verbatim on everything else. Names starting and ending with 2 underscores are
--: reserved to the implementation.
--:
--: Curly braces, can be escaped with backslashes or backtick characters. These
--: characters can be escaped by them self.
--:
--: Example Configuration File
--: ~~~~~~~~~~~~~~~~~~~~~~~~~~
--:
--: Pipadocs main objective is to scrape documentation comments from a project and generate
--: output in desired order. Such an basic approach would be insufficient for many common cases.
--: Thus pipadoc has facilities to generate and modify documentation in an extensible way.
--:
--: Pipadoc itself comes with a configuration file for generating it's own documentation and
--: assist the test suite. This is a good starting point for writing your own configuration.
--:
--: This configfile supports 'text' and 'asciidoc' back ends.
--:
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
--: Substitutions Macros
--: ^^^^^^^^^^^^^^^^^^^^
--:
--=shipped_config_subst
--:
--:
--: Dependencies
--: ~~~~~~~~~~~~
--:
--: 'pipadoc' does not depend on any external Lua libraries. Nevertheless modules can be loaded
--: optionally to augment the behavior and provide extra features. Plugin-writers should
--: use the 'request()' function instead the Lua 'require()', falling back to simpler but usable
--: functionality when some library is not available or call 'die()' when a reasonable fallback
--: won't do it.
--:
--: Pipadoc calls 'request "luarocks.loader"' to make rocks modules available when
--: installed.
--:
--:
--: Programming API for Extensions
--: ------------------------------
--:
--:
--: [[GLOBAL]]
--: Documentation Variables
--: ~~~~~~~~~~~~~~~~~~~~~~~
--:
--: The 'GLOBAL' and 'GLOBAL_POST' Lua tables holds key/value pairs of variables
--: with global definitions. These are used by the core and processors/'strsubst()'.
--: Simple string assignments can be set from the command line. Configuration files may define
--: more complex Lua functions for string substitutions.
--:
--:
--: Predefined Variables
--: ^^^^^^^^^^^^^^^^^^^^
--:
--: The 'GLOBAL' table is initialized with:
--:
--@GLOBAL
--:
--: The 'GLOBAL_POST' table is used for a final 'strsubst()' pass after postprocessing.
--: There are no values defined in 'GLOBAL_POST'.
--:
--: [[CONTEXT]]
--: The Context
--: ~~~~~~~~~~~
--:
--: Processors, operators, string substitution calls and diagnostics get a context
--: passed along. This context represents the state for the actual processed line plus
--: everything that's defined in GLOBAL.
--:
--: In a few cases a fake-context in angle brackets is passed around for diagnostic functions.
--:
--: Context Members
--: ^^^^^^^^^^^^^^^
--:
--: The following members are used/defined in 'contexts'.
--:
--@context
--:
--:
--: Exported Functions
--: ~~~~~~~~~~~~~~~~~~
--:
--: pipadoc exports some functions for the use in pre/post processors from config files.
--:
--=api_load
--=api_logging
--=api_typecheck
--=api_typeconv
--=api_strsubst
--=api_strsubst_example
--=api_filetypes
--=api_op
--=api_preproc
--=api_postproc
--=api_sections
--:
--: Other functions
--: ~~~~~~~~~~~~~~~
--:
--=api_various
--:
--:
--: [appendix]
--: Common Warnings
--: ---------------
--:
--: Pipadoc emits warnings on problems. Even with warnings processing will go on but the output
--: may need some attention.
--: Warnings are suppressed with the '--quiet' option.
--:
--PLANNED: sort warnings
--=cwarn
--:
--: [appendix]
--: Generate the Pipadoc Documentation
--: ----------------------------------
--:
--: 'pipadoc' documents itself with embedded asciidoc text. This can be extracted with
--:
--: ----
--: lua pipadoc.lua -m asciidoc pipadoc.lua >pipadoc.txt
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
--: There is a '--make-doc' option which calls the above commands. For convenience
--:
--:
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
--: License Explanation
--: ~~~~~~~~~~~~~~~~~~~
--:
--: The License (GPL) only applies to pipadoc and any derivative work. The purpose of pipadoc
--: is to extract documentation from other files, this does not imply that these source files
--: from which the documentation is extracted need to be licensed under the GPL, neither does
--: this imply that the extracted documentation need to be licensed under the GPL.
--: Using pipadoc for non-free software poses no problems about the Licensing terms of
--: this software.
--:
--: The GPL applies when you distribute pipadoc itself, in original or modified form. Since
--: pipadoc is written in the Lua scripting language, you already distribute its source as well,
--: which naturally makes this distribution conform with the GPL.
--:
--: Nevertheless, when you make any improvements to pipadoc please consider to contact
--: Christian Thäter <ct@pipapo.org> for including them into the mainline.
--:
--INDEX:
--: [index]
--: Index
--: -----
--:
--$INDEX
--:
--:

--PLANNED: DOCME, example section about one source can be used to generate different docs

--ISSUES:
--:
--: ISSUES
--: ------
--:
--: WIP
--: ~~~
--:
--$WIP
--:
--: FIXME
--: ~~~~~
--:
--$FIXME
--:
--PLANNED: only generate FIXME Section when there are FIXME's
--:
--: TODO
--: ~~~~
--:
--$TODO
--:
--PLANNED: only generate TODO section when there are TODO's
--:
--: PLANNED
--: ~~~~~~~
--:
--$PLANNED
--:
--PLANNED: only generate PLANNED section when there are PLANNED's
--:
--: DONE
--: ~~~~
--:
--$DONE
--:
--PLANNED: only generate DONE section when there are DONE's
--:


--PLANNED: named processors, define processing chains or sort by priority
--PLANNED: control language/conditionals?  //section?key \{condition\}  else becomes DROPPED:section_key
--PLANNED: not only pipadoc.conf but also pipadoc.sty templates, conf are local only configurations, .sty are global styles
--PLANNED: how to join (and then wordwrap) lines?
--PLANNED: insert empty lines on dedent
--PLANNED: bash like parameter expansion, how to apply that to sections/keys too --%{section}:%{key} .. how about strsubst on SECTION and ARG //{SECTION}:{ARG}
--PLANNED: INIT section for configuration
--PLANNED: test expected stderr in test suite
--PLANNED: DOCME documentation is usually only for one markup designed, dispatch on strsubst make only maintaining easier
--PLANNED: special sections
--PLANNED: CONFIG:PRE
--PLANNED: CONFIG:POST
--PLANNED: CONFIG:GENERATE
--PLANNED: manpage

--- Local Variables:
--- mode: lua
--- compile-command: "lua pipadoc.lua --issues --make-doc"
--- End:
