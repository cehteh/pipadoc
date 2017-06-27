--license:
--: pipadoc - Documentation extractor
--: Copyright (C)                        Pipapo Project
--:  2015, 2016, 2017                    Christian Thaeter <ct@pipapo.org>
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

--PLANNED: include operator, add a file to the processing list
--PLANNED: split on newlines
--PLANNED: merge lines, '+' operator?
--+        like this, note about indentation, no newline
--PLANNED: escape pipadoc to avoid wrong parsed pipadoc comments: char* bad="//here:"; //here: the first isn't pipadoc perhaps {DROP}
--PLANNED: true block comments --name(key makes every further line prepended
--+        with --name:key util --) is seen, 'PIPADOC:' overrides apply


CONTEXT = {
  --context:file `FILE`::
  --context:file   The file or section name currently processed or some special annotation
  --context:file   in angle brackets (eg '<startup>') on other processing phases
  --context:line `LINE`::
  --context:line   Current line number of input or section, or indexing key
  --context:line   Lines start at 1

  FILE = "<startup>"
}

DOCVARS = {
  --DOCVARS:nl `NL`::
  --DOCVARS:nl   The line-break character sequence, usually '\n' on unix systems but
  --DOCVARS:nl   can be changed with a command-line option
  NL = "\n",

  --DOCVARS:markup `MARKUP`::
  --DOCVARS:markup   The markup syntax (--markup option). This information is not
  --DOCVARS:markup   used by pipadoc itself but preprocessors and custom extensions
  --DOCVARS:markup   may use it.
  MARKUP = "text",
}

local args_done = false
local opt_verbose = 1
local opt_nodefaults = false
local opt_toplevel = "MAIN"
local opt_inputs = {}
local opt_config = "pipadoc_config.lua"


--PLANNED: log to PIPADOC_LOG section, later hooked in here
local printerr_hook

local function printerr(...)
  local line = ""

  for i,v in ipairs {...} do
    if i > 1 then
      line = line.."\t"
    end
    line = line..tostring(v)
  end
  line = line.."\n"

  io.stderr:write(line)
  if printerr_hook then
    printerr_hook(line)
  end
end

local function printlvl(lvl,...)
  if lvl <= opt_verbose then
    printerr(CONTEXT.FILE..":"..(CONTEXT.LINE and CONTEXT.LINE..":" or ""), ...)
  end
end


--api:
--:
--: Logging Progress and Errors
--: ~~~~~~~~~~~~~~~~~~~~~~~~~~~
--:
--: Here are few functions to log progress and report errors. All this functions take a
--: variable argument list. Any Argument passed to them will be converted to a string and printed
--: to stderr when the verbosity level is high enough.
--:
function warn(...) printlvl(1, ...) end  --: report a important but non fatal failure
function info(...) printlvl(2, ...) end  --: report normal progress
function dbg(...) printlvl(3, ...) end   --: show debugging information
function trace(...) printlvl(4, ...) end --: show more detailed progress information


function die(...) --: report a fatal error and exit the program
  printerr(...)
  os.exit(1)
end



-- debugging only
function dump_table(p,t)
  for k,v in pairs(t) do
    dbg(p,k,v)
    if type(v) == 'table' then
      dump_table(p.."/"..k, v)
    end
  end
end


--api:
--:
--: Dependencies
--: ~~~~~~~~~~~~
--:
--: 'pipadoc' does not depend on any external Lua libraries. The intention is to, by default, make
--: documentation build able on minimal target systems. Nevertheless Modules can be loaded optionally to augment
--: pipadocs behavior and provide extra features. Plugin-writers should try to adhere to this practice
--: if possible and use the 'request' function instead the Lua 'require'. Falling back to simpler but usable
--: functionality when some library is not available.
--:
--: When luarocks is installed, then the 'luarocks.loader' is loaded to make any module installed by luarocks
--: available.
--:
function request(name) --: try to load optional modules
  --:    wraps lua 'require' in a pcall so that failure to load a module results in 'nil' rather than a error
  local ok,handle = pcall(require, name)
  if ok then
    dbg("loaded:", name, handle._VERSION)
    return handle
  else
    warn("Can't load module:", name)
    return nil
  end
end


--api:
--:
--: Type checks
--: ~~~~~~~~~~
--:
--: Wrappers around 'assert' to check externally supplied data. On success 'var' will be returned
--: otherwise an assertion error is raised.
--:

function assert_type(var, expected) --: checks that the 'var' is of type 'expected'
  assert(type(var) == expected, "type error: "..expected.." expected, got "..type(var))
  return var
end

function maybe_type(var, expected) --: checks that the 'var' is of type 'expected' or nil
  assert(var == nil or type(var) == expected, "type error: "..expected.." or nil expected, got "..type(var))
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

--:
--: Type conversions
--: ~~~~~~~~~~~~~~~~
--:
--: Functions which do specific type conversions.
--:

function to_table(v) --: if 'v' is not a table then return +++\{v\}+++
  if type(v) ~= 'table' then
    return {v}
  else
    return v
  end
end

function to_text(v) --: convert 'v' to a string, returns 'nil' when that string would be empty
  v = tostring (v)
  if v ~= "" then
    return v
  else
    return nil
  end
end


--api:
--:
--: String evaluation
--: ~~~~~~~~~~~~~~~~~
--:
--: Documentation-text is passed to the streval() function which recursively evaluates lua expression inside
--: curly braces. This can be used to retrieve the value of variables, call or define functions. When the
--: text inside curly braces can not be evaluated it is retained verbatim. One can escape curly braces
--: with a backslash or a back-tick. Backslash and backtick can be escaped by them self.
--:
--: 'streval' tries first to do simple variable substitutions from the `CONTEXT` and `DOCVARS` tables. This
--: is always a safe operation and CONTEXT/DOCVARS does not need to be qualified.
--:
--: WARNING: String evaluation may execute lua code which is embedded in the documentation comments. This
--:          may lead to unsafe operation when the source is not trusted.
--PLANNED: safe/unsafe mode for disabling string evaluation, function calls only, not vars expansion
--:

-- for lua 5.1 compatibility
local loadlua
if _VERSION == "Lua 5.1" then
  loadlua = loadstring
else
  loadlua = load
end

local escapes = {
  __BACKSLASH__ = "\\",
  __BACKTICK__ = "`",
  __BRACEOPEN__ = "{",
  __BRACECLOSE__ = "}",
}

function streval (str) --: evaluate lua code inside curly braces in str.
  assert_type (str, "string")

  local function streval_intern (str)
    local ret= ""

    for pre,braced,post in str:gmatch("([^{]*)(%b{})([^{]*)") do
      local inbraced=braced:sub(2,-2)

      if #inbraced > 0 then

        if escapes[inbraced] then
          braced=escapes[inbraced]
        elseif CONTEXT[inbraced] then
          braced=CONTEXT[inbraced]
        elseif DOCVARS[inbraced] then
          braced=DOCVARS[inbraced]
        else
          inbraced = streval_intern(inbraced)
          if #inbraced > 0 then

            --PLANNED: execute only when safe
            local success,result = pcall(loadlua ("return ("..inbraced..")"))

            if success and result then
              braced = result or ""
            else
              success,result = pcall(loadlua (inbraced))
              if success then
                braced = result or ""
              end
            end
          end
        end
      end
      ret = ret..pre..tostring(braced)..post
    end

    return ret == "" and str or ret
  end

  return streval_intern(str:gsub("[`\\]([{}\\])",
                                 {
                                   ["\\"] = "{__BACKSLASH__}",
                                   ["`"] = "{__BACKTICK__}",
                                   ["{"] = "{__BRACEOPEN__}",
                                   ["}"] = "{__BRACECLOSE__}",
                                 }
                                ))
end


local function pattern_escape (p)
  return (p:gsub("%W", "%%%1"))
end

--sections:
--: Text in pipadoc is appended to named 'sections'. Sections are later brought into the desired order in a 'toplevel'
--: section. Text can be associated with some alphanumeric key under that section. This enables later sorting for indexes
--: and glossaries.
--:
--: Sections can be one line or span a block of lines.
--:
--: One line sections are defined when a section and maybe a key is followed by documentation text.
--: Block sections start with the section definition but no documentation text on the same line. A Block stays active
--: until the next block section definition. One line Doctext can be interleaved into Blocks.
--:
--: When no section is set in a file, then the block section name defaults to the files name up, but excluding to the
--: first dot.
--:
--: Pipadoc needs a recipe how to assemble all sections together. This is done in a 'toplevel' section which defaults to the
--: name 'MAIN'.
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
local sections = {}
local sections_usecnt = {}
local sections_keys_usecnt = {}

--api:
--:
--: Sections
--: ~~~~~~~~
--:

function section_append(section, key, context) --: Append data to the given section/key
  --:   section:::
  --:     name of the section to append to, must be a string
  assert_type(section, "string")
  --:   key:::
  --:     the subkey for sorting within that section. 'nil' for appending text to normal sections
  maybe_type(key, "string")
  --:   context:::
  --:     The source line broken down into its components and additional pipadoc metadata
  assert_type(context, "table")
  --:
  trace("append:", section, key, context.TEXT)
  sections[section] = sections[section] or {keys = {}}
  if key and #key > 0 then
    sections[section].keys[key] = sections[section].keys[key] or {}
    table.insert(sections[section].keys[key], context)
  else
    table.insert(sections[section], context)
  end
end

--filetypes:
--: Pipadoc needs to know about the syntax of line comments of the files it is reading. For this patterns are
--: registered to be matched against the file name together with a list of line comment characters.
--:
--: There are many definitions included for common filetypes already. For languages which support block comments
--: the opening (but not the closing) commenting characters are registered as well. This allows to define section
--: blocks right away. But using the comment closing sequence right on the line will clobber the
--: output, just don't do that!
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
--: /*fail: don't do this, pipadoc comments span to the end of the line */ void* text;
--: ----
--:
--: A special case is that when a line comment is defined as an empty string ("") then every line of a file is
--: considered as documentation but no special operations apply. This is used for plaintext documentation
--: files. Which also uses the "PIPADOC:" keyword to enable special operations within text files.
local filetypes = {}

--api:
--:
--: Filetypes
--: ~~~~~~~~~
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
  --: filetype_register("C", {"%.c$","%.cpp$","%.C$", "%.cxx$", "%.h$"}, {"//", "/*"})
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
    filetypes[filep[i]] = filetypes[filep[i]] or {language = name}
    for j=1,#linecommentseqs do
      dbg("register filetype:", name, filep[i], pattern_escape (linecommentseqs[j]))
      filetypes[filep[i]][#filetypes[filep[i]]+1] = pattern_escape(linecommentseqs[j])
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

local function comment_select (line, linecommentseqs)
  for i=1,#linecommentseqs do
    if string.match(line, linecommentseqs[i]) then
      return linecommentseqs[i]
    end
  end
end

local preprocessors = {}

--TODO: DOCME
function preprocessor_register (langpat, preprocess)
  assert_type (langpat, "string")
  dbg ("register preprocessor:", langpat, preprocess)

  if type (preprocess) == "table" then
    preprocess = function (str)
      return str:gsub (preprocess, preprocess[1], preprocess[2], preprocess[3])
    end
  end

  if type (preprocess) == "function" then
    table.insert(preprocessors, {pattern=langpat, preprocessor=preprocess})
  else
    warn ("Unsupported preprocessor type")
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
          trace ("add preprocessor for:", k, ppdesc.preprocessor)
          table.insert(filetype_preprocessors, ppdesc.preprocessor)
          v.preprocessors = filetype_preprocessors
        end
      end
    end
  end
end

--op:
--: Operators define how documentation comments are evaluated, they are the core functionality of pipadoc and mandatory in the pipadoc
--: syntax to define a pipadoc comment line. It is possible (but rarely needed) to define additional
--: operators. Operators must be a single punctuation character.
local operators = {}


--PLANNED: operator_register(char, read, generate) .. add generator function here too
--api:
function operator_register(char, func) --: Register a new operator
  --:   char:::
  --:     single punctuation character defining this operator
  --:   func:::
  --:     a function which receives a table of the 'context' parsed from the pipadoc comment line
  --:
  --: Operators drive the main functionality, like invoking the processors and generating the output.
  --:
  assert(string.match(char, "^%p$") == char)
  assert_type(func, 'function')
  dbg("register operator:", char)
  operators[char] = assert_type(func, 'function')
end


local operator_pattern_cache

function operator_pattern()
  if not operator_pattern_cache then
    operator_pattern_cache= "["
    for k in pairs(operators) do
      operator_pattern_cache = operator_pattern_cache..k
    end
    operator_pattern_cache = operator_pattern_cache.."]"
  end
  return operator_pattern_cache
end


function add_inputfile(filename) --: Add a file to the processing list
  assert_type(filename, "string")
  opt_inputs[#opt_inputs+1] = filename
end

--usage:
local options = {
  "pipadoc [options...] [inputs..]",  --:  {STRING}
  "  options are:", --:  {STRING}

  "    -v, --verbose", --:  {STRING}
  "                        increment verbosity level", --:  {STRING}
  ["-v"] = "--verbose",
  ["--verbose"] = function ()
    opt_verbose = opt_verbose+1
    dbg("verbose:", opt_verbose)
  end,
  "", --:  {STRING}

  "    -q, --quiet", --:  {STRING}
  "                        suppresses any messages", --:  {STRING}
  ["-q"] = "--quiet",
  ["--quiet"] = function () opt_verbose = 0 end,
  "", --:  {STRING}

  "    -d, --debug", --:  {STRING}
  "                        set verbosity to maximum", --:  {STRING}
  ["-d"] = "--debug",
  ["--debug"] = function ()
    opt_verbose = 3
    dbg("verbose:", opt_verbose)
  end,
  "", --:  {STRING}

  "    -h, --help", --:  {STRING}
  "                        show this help", --:  {STRING}
  ["-h"] = "--help",
  ["--help"] = function ()
    usage()
  end,
  "", --:  {STRING}


  "    -r, --register <name> <file> <comment>", --:  {STRING}
  "                        register a filetype pattern", --:  {STRING}
  "                        for files matching a file pattern", --:  {STRING}
  ["-r"] = "--register",
  ["--register"] = function (arg,i)
    assert(type(arg[i+3]))
    filetype_register(arg[i+1], arg[i+2], arg[i+3])
    return 3
  end,
  "", --:  {STRING}


  "    -t, --toplevel <name>", --:  {STRING}
  "                        sets 'name' as toplevel node [MAIN]", --:  {STRING}
  ["-t"] = "--toplevel",
  ["--toplevel"] = function (arg, i)
    assert(type(arg[i+1]))
    opt_toplevel = arg[i+1]
    dbg("toplevel:", opt_toplevel)
    return 1
  end,
  "", --:  {STRING}

  "    -c, --config <name>", --:  {STRING}
  "                        selects a config file [pipadoc_config.lua]", --:  {STRING}
  ["-c"] = "--config",
  ["--config"] = function (arg, i)
    assert(type(arg[i+1]))
    opt_config = arg[i+1]
    dbg("config:", opt_config)
    return 1
  end,
  "", --:  {STRING}


  "    --no-defaults", --:  {STRING}
  "                        disables default filetypes and processors", --:  {STRING}
  ["--no-defaults"] = function ()
    opt_nodefaults = true
    dbg("nodefaults")
  end,
  "", --:  {STRING}


  --TODO: document where markup is used (custom preprocessor/generators hooks?)
  "    -m, --markup <name>", --:  {STRING}
  "                        selects the markup engine for the output [text]", --:  {STRING}
  ["-m"] = "--markup",
  ["--markup"] = function (arg, i)
    assert(type(arg[i+1]))
    DOCVARS.MARKUP = arg[i+1]
    dbg("markup:", DOCVARS.MARKUP)
    return 1
  end,
  "", --:  {STRING}

  -- intentionally undocumented option
  ["--make-doc"] = function (arg, i)
    os.execute("lua pipadoc.lua -m asciidoc -q pipadoc.lua >pipadoc.txt")
    os.execute("asciidoc -a toc pipadoc.txt")
    os.execute('a2x -L -k -v --dblatex-opts "-P latex.output.revhistory=0" pipadoc.txt')
    return 1
  end,

  "    --", --:  {STRING}
  "                        stops parsing the options and treats each", --:  {STRING}
  "                        following argument as input file", --:  {STRING}
  ["--"] = function () args_done=true end,

  --TODO: --alias match pattern --file-as match filename
  --TODO: -o --output
  --TODO: -l --load
  --TODO: --features  show a report which features (using optional lua modules) are available
  --TODO: list-operators
  --TODO: list-sections
  --TODO: force filetype variant  foo.lua:.txt
  --TODO: eat (double, triple, ..) empty lines
  --TODO: add debug report (warnings/errors) to generated document PIPADOC_LOG section
  --TODO: line ending \n \r\n
  --TODO: --define -D name=value for setting DOCVARS
  --TODO: wrap at blank/intelligent
  --PLANNED: wordwrap
  --PLANNED: some flags get defaults from the config file

  "", --:  {STRING}
  "  inputs are file names or a '-' which indicates standard input", --:  {STRING}
}

function usage()
  print("usage:")
  for i=1,#options do
    print(options[i])
  end
  os.exit(0)
end


function parse_args(arg)
  CONTEXT = {
    FILE="<parse_args>"
  }

  local i = 1
  while i <= #arg do
    CONTEXT.LINE=i
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
        die("optarg error")
      end
    end
    i = i+1
  end
end

-- store state for block comments
local block_section
local block_arg

local function setup()
  parse_args(arg)
  CONTEXT = {
    FILE="<setup>"
  }
  request "luarocks.loader"
  --PLANNED: for pattern matching etc
  --lfs = request "lfs"
  --posix = request "posix"

  do
    local date = os.date ("*t")
    --DOCVARS:date `YEAR, MONTH, DAY, HOUR, MINUTE`::
    --DOCVARS:date   Current date information
    DOCVARS.YEAR = date.year
    DOCVARS.MONTH = date.month
    DOCVARS.DAY = date.day
    DOCVARS.HOUR = date.hour
    DOCVARS.MINUTE = date.min
    --DOCVARS:date `DATE`::
    --DOCVARS:date   Current date in YEAR/MONTH/DAY format
    DOCVARS.DATE = date.year.."/"..date.month.."/"..date.day
  end

  if not opt_nodefaults then
    --PLANNED: read style file like a config, lower priority, different paths (./ /etc/ ~/ ...)
    if opt_config then
      dbg ("load config:", opt_config)
      local config = loadfile(opt_config)

      if config then
        config ()
      else
        warn ("Can't load config file:", opt_config)
      end

    end

    --PLANNED: write preprocessor macro to expand filetype_register() as documentation
    --filetypes_builtin:scons * SCons
    filetype_register("scons", "^SConstuct$", "#")

    --filetypes_builtin:cmake * CMake
    filetype_register("cmake", {"^CMakeLists.txt$","%.cmake$"}, {"#", "#[["})

    --filetypes_builtin:c * C, C++, Headerfiles
    filetype_register("c", {"%.c$","%.cpp$", "%.C$", "%.cxx$", "%.h$", "%.hpp$", "%.hxx$"}, {"//", "/*"})

    --filetypes_builtin:lua * Lua
    filetype_register("lua", {"%.lua$"}, "--")

    --filetypes_builtin:automake * Autoconf, Automake
    filetype_register("automake", {"%.am$", "%.in$", "^configure.ac$"}, {"#", "dnl"})

    --filetypes_builtin:make * Makefiles
    filetype_register("makefile", {"^Makefile$", "%.mk$", "%.make$"}, "#")

    --filetypes_builtin:shell * Shell
    filetype_register("shell", {"%.sh$", "%.pl$", "%.awk$", }, "#")

    --filetypes_builtin:perl * Perl
    filetype_register("perl", {"%.pl$", }, "#")

    --filetypes_builtin:awk * AWK
    filetype_register("awk", {"%.awk$", }, "#")

    --filetypes_builtin:prolog * Prolog
    filetype_register("prolog", {"%.yap$", "%.pro$", "%.P$"}, "%")

    --filetypes_builtin:text * Textfiles, Pipadoc (`.pdoc`)
    filetype_register("text", {"%.txt$", "%.TXT$", "%.pdoc$", "^-$"}, {"PIPADOC:", ""})

    --filetypes_builtin:java * Java, C#
    filetype_register("java", {"%.java$", "%.cs$"}, {"//", "/*"})

    --filetypes_builtin:objective_c * Objective-C
    filetype_register("objc", {"%.h$", "%.m$", "%.mm$"}, {"//", "/*"})

    --filetypes_builtin:python * Python
    filetype_register("python", "%.py$", "#")

    --filetypes_builtin:visualbasic * Visual Basic
    filetype_register("visualbasic", "%.vb$", "'")

    --filetypes_builtin:php * PHP
    filetype_register("php", "%.php%d?$", {"#", "//", "/*"})

    --filetypes_builtin:javascript * Javascript
    filetype_register("javascript", "%.js$", "//", "/*")

    --filetypes_builtin:delphi * Delphi, Pascal
    filetype_register("delphi", {"%.p$", "%.pp$", "^%.pas$"}, {"//", "{", "(*"})

    --filetypes_builtin:ruby * Ruby
    filetype_register("ruby", "%.rb$", "#")

    --filetypes_builtin:sql * SQL
    filetype_register("sql", {"%.sql$", "%.SQL$"}, {"#", "--", "/*"})
  end

  --op_builtin:
  --: `:` ::
  --:   The documentation operator. Defines normal documentation text. Each pipadoc comment using the `:`
  --:   operator is processed as potential documentation. First all enabled 'processors' are run over it and
  --:   finally the text is appended to the current section(/key)
  operator_register(
    ":",
    function (context)

      if context.TEXT ~= "" and (context.SECTION or context.ARG) then
        --oneline
        context.SECTION = context.SECTION or block_section
        context.ARG = context.ARG or block_arg
        section_append(context.SECTION, context.ARG, context)
      elseif context.TEXT == "" and (context.SECTION or context.ARG) then
        --block head
        block_section = context.SECTION or block_section
        block_arg = context.ARG -- or block_arg
      else
        --block cont
        context.SECTION = context.SECTION or block_section
        context.ARG = context.ARG or block_arg
        section_append(context.SECTION, context.ARG, context)
      end
    end
  )


  --op_builtin:
  --: `=` ::
  --:   Section paste operator. Takes a section name as argument and will paste that section in place.
  operator_register(
    "=",
    function (context)
      context.SECTION = context.SECTION or block_section

      if #context.ARG > 0 then
        section_append(context.SECTION, nil, context)
      else
        warn("include argument missing:")
      end
    end
  )

  --op_builtin:
  --: `@` ::
  --:   Takes a section name as argument and will paste section text alphabetically sorted by their keys.
  --PLANNED: option for sorting locale
  --PLANNED: option for sorting (up/down)
  operator_register(
    "@",
    function (context)
      context.SECTION = context.SECTION or block_section

      if #context.ARG > 0 then
        section_append(context.SECTION, nil, context)
      else
        warn("sort argument missing:")
      end
    end
  )


  --op_builtin:
  --: `#` ::
  --:   Takes a section name as argument and will paste section text numerically sorted by their keys.
  --PLANNED: option for sorting (up/down)
  operator_register(
    "#",
    function (context)
      context.SECTION = context.SECTION or block_section

      if #context.ARG > 0 then
        section_append(context.SECTION, nil, context)
      else
        warn("sort argument missing:")
      end
    end
  )

  preprocessors_attach ()
end


local function process_line (line, comment, filecontext)
  local context = {
    FILE = filecontext.FILE,
    LINE = filecontext.LINE,
  }
  CONTEXT=context

  local preprocessors = filecontext.filetype.preprocessors
  if preprocessors then
    for i=1,#preprocessors do
      local linepp = preprocessors[i](line)
      --PLANNED: preprocessors may expand to multiple lines?
      if to_text (linepp) and line ~= linenew then
        line = linepp
        trace("preprocessed:", line)
      end
    end
  end

  --context:
  --:pre `PRE`::
  --:pre   Contains the sourcecode in before the linecomment.
  --:pre   To be used by preprocessors to gather information.
  --:comment `COMMENT`::
  --:comment   Character sequence which was used as line comment.
  --:section `SECTION`::
  --:section   Section where the documentation should appear.
  --:op `OP`::
  --:op   Single punctuation Operator defining how to process this line.
  --:arg `ARG`::
  --:arg   Optional argument to the operator. This can be the sort key
  --:arg   (alphabetic or numeric) or another section name for pasting.
  --:text `TEXT`::
  --:text   The actual Documentation Text.

  -- special case for plaintext files
  if comment == "" then
    context.PRE, context.COMMENT, context.SECTION, context.OP, context.ARG, context.TEXT =
      "", " ", nil, ":", nil, line
  else
    local pattern = "^(.-)("..comment..")([%w_.]*)("..operator_pattern()..")([%w_.]*)%s?(.*)$"
    dbg("pattern:", pattern)
    context.PRE, context.COMMENT, context.SECTION, context.OP, context.ARG, context.TEXT =
      string.match(line,pattern)
    context.SECTION = to_text(context.SECTION)
    context.ARG = to_text(context.ARG)
  end

  if context.PRE then
    trace("pre:", context.PRE, "section:", context.SECTION, "op:", context.OP, "arg:", context.ARG, "text:", context.TEXT)

    local op = context.OP
    if op then
      if operators[op] then
        while operators[op] do
          op = operators[op]
        end
        op(context)
      else
        warn("unknown operator:", op)
      end
    end
  end
end

local function process_file(file)
  local filetype = filetype_get (file)
  if not filetype then
    warn("unknown file type:", file)
    return
  end

  -- filecontext is a partial context storing data
  -- of the current file processed
  local filecontext = {
    FILE="<process_file>",
    filetype=filetype
  }
  CONTEXT=filecontext

  local fh
  if file == '-' then
    filecontext.FILE = "<stdin>"
    fh = io.stdin
  else
    fh = io.open(file)
    if not fh then
      warn("file not found:", file)
      return
    end
    filecontext.FILE = file
  end

  --context:section `SECTION`::
  --context:section   stores the current section name
  block_section = filecontext.FILE:match("[^./]+%f[.%z]")
  dbg("section:", block_section)

  filecontext.LANGUAGE = filetype.language
  dbg("language:", filecontext.LANGUAGE)

  filecontext.LINE=0
  for line in fh:lines() do
    filecontext.LINE = filecontext.LINE +1
    trace("input:", line)

    local comment = comment_select(line, filetype)

    if comment then
      process_line(line, comment, filecontext)
    end
  end
  fh:close()
end

local function process_inputs()
  for i in ipairs(opt_inputs) do
      process_file(opt_inputs[i])
  end
end




local default_generators = {
  [":"] = function (context)
    local ret = streval(context.TEXT)
    if ret == "" and to_text (context.TEXT) then
      return ""
    else
      trace ("generate:"..context.FILE..":"..context.LINE, ret)
      return ret.."\n"
    end
  end,

  ["="] = function (context)
    return generate_output(context.ARG)
  end,

  ["@"] = function (context)
    dbg("generate_output_alphasorted:"..context.FILE..":"..context.LINE)
    local which = context.ARG
    local section = sections[which] and sections[which].keys
    local text = ""

    if section ~= nil then
      sections_keys_usecnt[which] = sections_keys_usecnt[which] + 1

      local oldfile = context.FILE
      context.FILE ='<output>:'..which

      local sorted = {}

      for k in pairs(section) do
        if not tonumber (k) then
          table.insert(sorted, k)
        end
      end

      table.sort(sorted, function(a,b) return tostring(a) < tostring(b) end)

      if #sorted == 0 then
        warn("section is empty:",which)
        return ""
      end

      for i=1,#sorted do
        context.LINE=sorted[i]
        for j=1,#section[sorted[i]] do
          text = text..section[sorted[i]][j].TEXT..'\n'
        end
      end
      context.FILE = oldfile
    else
      warn("no section named:", which)
    end
    return text
  end,

  ["#"] = function (context)
    dbg("generate_output_numsorted:"..context.FILE..":"..context.LINE)
    local which = context.ARG
    local section = sections[which] and sections[which].keys
    local text = ""

    if section ~= nil then
      sections_keys_usecnt[which] = sections_keys_usecnt[which] + 1

      local oldfile = context.FILE
      context.FILE ='<output>:'..which

      local sorted = {}

      for k in pairs(section) do
        if tonumber (k) then
          table.insert(sorted, k)
        end
      end

      table.sort(sorted, function(a,b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)

      if #sorted == 0 then
        warn("section is empty:",which)
        return ""
      end

      for i=1,#sorted do
        context.LINE=sorted[i]
        for j=1,#section[sorted[i]] do
          text = text..section[sorted[i]][j].TEXT..'\n'
        end
      end
      context.FILE = oldfile
    else
      warn("no section named:", which)
    end
    return text
  end,
}




local sofar_rec={}

--PLANNED: register generators possibly togehter with register operator
function generate_output(which, generators)
  local context = {
    FILE = "<output>"
  }
  CONTEXT = context

  dbg("generate_output:", which)
  generators = generators or default_generators
  local section = sections[which]
  local text = ""

  if section ~= nil then
    if sofar_rec[which] then
      warn("recursive include:",which)
      return ""
    end
    if #section == 0 then
      warn("section is empty:",which)
      return ""
    end
    sofar_rec[which] = true
    sections_usecnt[which] = sections_usecnt[which] + 1

    context.FILE = '<output>:'..which
    for i=1,#section do
      context.LINE=i
      --TODO: DOCME actions
      local genfunc = generators[section[i].OP]
      if genfunc then
        CONTEXT=section[i]
        text = text .. genfunc(section[i])
        CONTEXT=context
      else
        warn("no generator function for:", section[i].OP)
      end
    end
    sofar_rec[which] = nil
  else
    warn("no section named:", which)
  end
  return text
end


setup()
process_inputs()

--PLANNED: document doublete/orphan checker
--PLANNED: refactor doublete/orphan into function

-- initialize orphans / doublets checker
for k,_ in pairs(sections) do
  if #sections[k] > 0 then
    sections_usecnt[k] = 0
  end

  if next(sections[k].keys) then
    sections_keys_usecnt[k] = 0
  end
end

io.write(generate_output(opt_toplevel))

-- orphans / doublets
local orphan = {
  FILE = "<orphan>"
}

local doublette = {
  FILE = "<doublette>"
}

for k,v in pairs(sections_usecnt) do
  if v == 0 then
    CONTEXT = orphan
    warn("section unused:", k)
  elseif v > 1 then
    CONTEXT = doublette
    warn("section multiple times used:", k, v)
  end
end


for k,v in pairs(sections_keys_usecnt) do
  if v == 0 then
    CONTEXT = orphan
    warn("section w/ keys unused:", k)
  elseif v > 1 then
    CONTEXT = doublette
    warn("section w/ keys multiple times used:", k, v)
  end
end


--MAIN:
--: pipadoc - Documentation extractor
--: =================================
--: :author:   Christian Thaeter
--: :email:    ct@pipapo.org
--: :date:     {os.date()}
--:
--:
--: Introduction
--: ------------
--:
--: Embedding documentation in program source files often yields the problem that the
--: structure of a program is not the optimal structure for the associated documentation.
--: Still there are many good reasons to maintain documentation together with the source right within
--: the code which defines the documented functionality. Pipadoc addresses this problem by extracting
--: special comments out of a source file and let one define rules how to compile the
--: documentation into proper order.  This is somewhat similar to ``literate Programming'' but
--: it puts the emphasis back to the code.
--:
--: Pipadoc is programming language and documentation system agnostic, all it requires is that
--: the programming language has some form of comments starting with a defined character sequence
--: and spanning to the end of the source line. Moreover documentation parts can be written in plain text
--: files aside from the sources.
--:
--:
--: History
--: -------
--:
--: This 'pipadoc' implemented in Lua follows an earlier implementation with a slightly different
--: (incompatible) syntax and less features which was implemented in AWK. Updating to the new syntax
--: should be straightforward and is suggested for any projects using pipadoc.
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
--: Pipadoc is single lua source file `pipadoc.lua` which is portable among most Lua versions
--: (PUC Lua 5.1, 5.2, 5.3, Luajit, Ravi). It ships with a `pipadoc.install` shell script which figures a
--: suitable Lua version out and installs `pipadoc.lua` as `pipadoc` in a given directory or the current
--: directory by default.
--:
--: There are different ways how this can be used in a project:
--:
--: - One can rely on a pipadoc installed in $PATH and just call that from the build tool chain
--: - When a installed Lua version is known from the build tool chain one can include the `pipadoc.lua`
--:   into the project and call it with the known Lua interpreter.
--: - One can ship the `pipadoc.lua` and `pipadoc.install` and do a local install in the build
--:   directory and use this pipadoc thereafter
--:
--FIXME: Pipadoc tries to load
--:
--:
--: Usage
--: -----
--:
--: .....
--=usage
--: .....
--:
--:
--: Basic concepts
--: --------------
--:
--: Pipadoc is controlled by special line comments. This is chosen because the most common denominator
--: between almost all programming languages is that they have some form of 'line comment', that is some
--: character sequence which defines the rest of the line as comment.
--:
--: This line comments are enhanced by a simple syntax to make them pipadoc comments. The comment
--: character sequence followed directly (without any extra space character) by some definition (see below)
--: becomes a pipadoc comment.
--:
--: Pipadoc processes the given files in phases. First all given files are read and parsed and finally the output is
--: generated by bringing all accumulated documentation parts together into proper order.
--TODO: rephrase above paragraph
--:
--: [[syntax]]
--: Pipadoc Syntax
--: ~~~~~~~~~~~~~~
--:
--: Any 'line-comment' of the programming language directly (without spaces) followed by a optional
--: alphanumeric section name, followed by an operator, followed by an optional argument and then the
--: documentation text. Only lines qualify this syntax are processed as pipadoc documentation.
--:
--: The formal syntax looks like:
--:
--: ____
--:  pipadoc = [source] <line comment> [section] <operator> [arg] [..space.. [documentation_text]]
--:
--:  source = ..any source code text..
--:
--:  linecomment = ..the linecomment sequence chosen by the filetype..
--:
--:  section = ..alphanumeric text including underscore and dots, but without spaces..
--:
--:  operator = [:=@#] by default, one of the defined operators
--:
--:  arg = ..alphanumeric text including underscore and dots, but without spaces..
--:
--:  documentation_text = ..rest of the line, free form text..
--: ____
--:
--:
--: Documentation lines are processed according to their operator.
--:
--TODO: DOCME oneline vs block, default section name, MAIN section
--TODO: note that literal strings are not special
--:
--: Order of operations
--: ~~~~~~~~~~~~~~~~~~~
--:
--: Pipadoc reads all files line by line, when a line contains a pipadoc comment (see <<syntax>> above)
--: it is processed in the following order:
--:
--: Preprocessing ::
--:   One can register preprocessors for each filetype. This preprocessors are
--:   lua functions who may alter the entire content of a line before any further processing.
--:
--: Parsing ::
--:   The line is broken down into its components and appended to its Section/Key store.
--:
--: Output Generation ::
--:   After all files are read the output is generated by starting assembling the toplevel section
--:   ('MAIN' if not otherwise defined).
--:
--: It is important to know that reading happens only line by line, operations can not span lines.
--: Preprocessing and Parsing may be stateful and thus preserve information for further processing.
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
--TODO: optarg
--:
--: pipadoc has builtin support for following languages
--: ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
--:
--@filetypes_builtin
--:
--:
--: Operators
--: ---------
--:
--=op
--TODO: optarg
--:
--: Built in operators
--: ~~~~~~~~~~~~~~~~~~
--:
--=op_builtin
--:
--:
--: [[DOCVARS]]
--: Documentation Variables
--: -----------------------
--:
--: The 'DOCVARS' Lua table holds key/value pairs of variables with the global state
--: of pipadoc. These can be used by the core and plugins in various ways. Debugging
--: for example prints the FILE:LINE processed and there is the 'varsubst' processor
--: to substitute them in the documentation text. The user can set arbitrary DOCVARS
--: from command line.
--TODO: optarg
--:
--: Predefined DOCVARS
--: ~~~~~~~~~~~~~~~~~~
--:
--@DOCVARS
--:
--: [[CONTEXT]]
--: The Context
--: -----------
--:
--: The current state and parsed information is stored in 'context' tables.
--: There is on global +CONTEXT+ variable which always references the current
--: context. In some execution phases this may be a partial/fake context which
--: is only instantiated with necessary information for debugging/logging.
--: Usually the +FILE+ member is then put into angle brakets.
--:
--: CONTEXT members
--: ~~~~~~~~~~~~~~~
--:
--: The following members are used in 'contexts'. `FILE` is always set to something
--: meaningful. The other members are optional.
--:
--@context
--:
--: Programming API for extensions
--: ------------------------------
--:
--: Lua functions specific to pipadoc which can be used by plugins.
--:
--=api
--:
--:
--: How to generate the pipadoc documentation itself
--: ------------------------------------------------
--:
--: 'pipadoc' documents itself with embedded asciidoc text. This can be extracted with
--:
--: ----
--: lua pipadoc.lua -m asciidoc -d pipadoc.lua >pipadoc.txt
--: ----
--:
--: The resulting `pipadoc.txt` can then be processed with the asciidoc tool chain to produce
--: distribution formats:
--:
--: -----
--: # generate HTML
--: asciidoc -a toc pipadoc.txt
--:
--: # generate PDF
--: a2x -L -k -v --dblatex-opts "-P latex.output.revhistory=0" pipadoc.txt
--: ----
--:
--: GNU General Public License
--: --------------------------
--:
--: ----
--=license
--: ----
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
--: pipadoc is written in the lua scripting language, you already distribute its source as well,
--: which naturally makes this distribution conform with the GPL.
--:
--: Nevertheless, when you make any improvements to pipadoc please consider to contact
--: Christian Thäter <ct@pipapo.org> for including them into the mainline.
--:
--ISSUES:
--:
--: ISSUES
--: ------
--:
--: FIXME
--: ~~~~~
--:
--=FIXME
--:
--FIXME: only generate FIXME Section when there are FIXME's
--:
--: TODO
--: ~~~~
--:
--=TODO
--:
--FIXME: only generate TODO section when there are TODO's
--:
--: PLANNED
--: ~~~~~~~
--:
--=PLANNED
--:
--FIXME: only generate PLANNED section when there are PLANNED's
--:

--PLANNED: control language/conditionals?  //section?key {condition}  else becomes DROPPED:section_key
--TODO: asciidoc //source:line// comments like old pipadoc
--TODO: integrate old pipadoc.txt documentation
--PLANNED: not only pipadoc.conf but also pipadoc.sty templates, conf are local only configurations, .sty are global styles
--PLANNED: how to join (and then wordwrap) lines?
--PLANNED: bash like parameter expansion, how to apply that to sections/keys too --%{section}:%{key}
--PLANNED: org-mode processor
--PLANNED: INIT section for configuration


--TODO: special sections
--TODO: CONFIG:PRE
--TODO: CONFIG:POST
--TODO: CONFIG:GENERATE

--- Local Variables:
--- mode: lua
--- compile-command: "lua pipadoc.lua -t ISSUES -q pipadoc.lua"
--- End:
