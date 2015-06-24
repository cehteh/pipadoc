--LICENSE:
--: Copyright (C)                        Pipapo Project
--:  2015,                               Christian Thaeter <ct@pipapo.org>
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

--PLANNED: directives: --! luacall()

local args_done = false
local opt_verbose = 1
local opt_nodefaults = false
local opt_toplevel = "MAIN"
local opt_inputs = {}

local docvars = {
  --docvars:file   `FILE`::
  --docvars:file     The file or section name currently processed or some special annotation
  --docvars:file     in angle brakets (eg '<startup>') on other processing phases
  FILE = "<startup>",
  --docvars:line   `LINE`::
  --docvars:line     Current line number of input or section, or indexing key
  --docvars:line     Lines start at 1, if set to 0 then some output formatters skip over it
  LINE = 0,
  --docvars:nl   `NL`::
  --docvars:nl     The linebreak character sequence, usually '\n' on unix systems but
  --docvars:nl     can be changed with a commandline option
  NL = "\n",
}


--PLANNED: macros/docvars  LUA_FUNC = "VERBATIM<function%s*(.-%))>::\n "

--PLANNED: log to PIPADOC_LOG section, later hooked in here
local printerr_hook

function printerr(...)
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

function msg(lvl,...)
  if lvl <= opt_verbose then
    printerr(docvars.FILE..":"..(docvars.LINE ~= 0 and docvars.LINE..":" or ""), ...)
  end
end


--api:
--: Logging Progress and Errors
--: ~~~~~~~~~~~~~~~~~~~~~~~~~~~
--:
--: There are few function to log progress and report errors. All this functions take a
--: variable argument list. Any Argument passed to them will be converted to a string and printed
--: to stderr when the verbosity level is high enough.
--:
function warn(...) msg(1, ...) end  --: `VERBATIM<function%s*(.-%))>`::%NL%  report a important but non fatal failure %NL%
function echo(...) msg(2, ...) end  --: `VERBATIM<function%s*(.-%))>`::%NL%  report normal progress %NL%
function dbg(...) msg(3, ...) end  --: `VERBATIM<function%s*(.-%))>`::%NL%  show verbose/debugging progress information %NL%

--PLANNED: use echo() for progress

function die(...) --: `VERBATIM<function%s*(.-%))>`::%NL%  report a fatal error and exit the programm %NL%
  printerr(...)
  os.exit(1)
end


--api:
--: Optional Lua Modules
--: ~~~~~~~~~~~~~~~~~~~~
--:
--: 'pipadoc' does not depend on any nonstandard Lua libraries, because they may not be installed on the target
--: system. But some modules can be loaded optionally to augment its behavior and provide extra features.
--: Plugin-writers should try to adhere to this practice if possible and use the 'request' function instead the
--: Lua 'require'.
--:
--: When luarocks is installed, then the 'luarocks.loader' is loaded by default to make any moduke installed by
--: luarocks available.
--:
function request(name) --: `VERBATIM<function%s*(.-%))>`::
  --:   try to load optional modules
  --:   wraps lua 'require' in a pcall so that failure to load a module results in 'nil' rather than a error  %NL%
  local ok,handle = pcall(require, name)
  if ok then
    return handle
  else
    warn("Can't load module:", name)
    return nil
  end
end

--PLANNED: for pattern matching etc
request "luarocks.loader"
--lfs = request "lfs"
--posix = request "posix"


--api:
--: Typechecks
--: ~~~~~~~~~~
--:
--: There are some wrapers around 'assert' to check externally supplied data. On success 'var' will be returned
--: otherwise an assertion error is raised.
--:
function assert_type(var, expected) --: `VERBATIM<function%s*(.-%))>`::%NL%  checks that the 'var' is of 'type' %NL%
  assert(type(var) == expected, "type error: "..expected.." expected")
  return var
end

function assert_char(var) --: `VERBATIM<function%s*(.-%))>`::%NL%  checks that 'var' is a single character %NL%
  assert(type(var) == "string" and #var == 1, "type error: single character expected")
  return var
end

function assert_notnil(var) --: `VERBATIM<function%s*(.-%))>`::%NL%  checks that 'var' is not 'nil' %NL%
  assert(type(var) ~= "nil", "Value expected")
  return var
end


function to_table(v)
   if type(v) ~= 'table' then
      v = {v}
   end
   return v
end

--sections:
--: Text in pipadoc is appended to 'sections'. This sections associated with a name. This sections are later brought in order
--: in a 'toplevel' section. Additionally instead just appending text to a named section, text can be appended under some
--: alphanumeric key under that section. This enables later sorting for indexes and glossaries.
--:
--: Sections can span a block of lines (until another section is set) or one-line setting a section only for the current
--: comment line. Section blocks are selected when the pipadoc comment defines a section and maybe a key but the rest of the
--: is empty, every subsequent line which does not define a new section block is then appended to the current block.
--:
--: One-Line sections are pipadoc comments which define a section and maybe a key and include some documentation text right
--: away.
--:
--: When no section is set in a file, then the block section name defaults to the files name up, but excluding to the first dot.
--:
--: Pipadoc needs a receipe how to assemble all sections togehter. This is done in a 'toplevel' section which defaults to the
--: name 'MAIN'.
--:
--: .An example document (assume the name example.sh)
--: ----
--: #!/bin/sh
--: #: here the default section is 'example', derrived from 'example.sh'
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
--: here the default section is 'example', derrived from 'example.sh'
--: back to the 'example' section
--: and finally 'oneline' alphabetically sorted by keys
--: this is appended to the section 'oneline' under key 'a'
--: this is appended to the section 'oneline' under key 'o'
--: ----
--:
--FIXME: check syntax for --:key in block and oneline context
sections = {}
-- local sections_usecnt = {}

--api:
--: Sections
--: ~~~~~~~~
--:
function section_append(section, key, action, value) --: `VERBATIM<function%s*(.-%))>`::
  --:   section:::
  --:     name of the section to append to, must be a string
  assert_type(section, "string")
  --:   key:::
  --:     the subkey for sorting within that section. 'nil' for appending text to normal sections
  --:   action:::
  --:     how to process the value in output, currently "text", "include" and "sort" are defined
  --:   value:::
  --:     the parameter for the action, usually the text to be included in the output.
  --:
  --:   Append data to the given section/key
  sections[section] = sections[section] or {keys = {}}
  if key and #key > 0 then
    sections[section].keys[key] = sections[section].keys[key] or {}
    table.insert(sections[section].keys[key], value)
  else
    table.insert(sections[section], {action = action, text = value})
  end
  dbg(action.. ":", section.."["..(key and #key > 0 and key .."]["..#sections[section].keys[key] or #sections[section]).."]:", value)
end

--api:
function section_get(section, key, index) --: `VERBATIM<function%s*(.-%))>`::
  --:   section:::
  --:     name of the section to append to, must be a string
  assert_type(section, "string")
  --:   key:::
  --:     the subkey for sorting within that section. maybe 'nil'
  --:   index:::
  --:     line number to query, when 'nil' defaults to the last line
  --:   returns:::
  --:     action, value pair or nil
  --:
  --:   query the action and value of the given section/key at index (or at end)
  if not sections[section] then
    return
  end

  if not key then
    index = index or #sections[section]
    echo("nokey",index, sections[section][index].action, sections[section][index].text)
    return sections[section][index].action, sections[section][index].text
  else
    index = index or #sections[section].keys
    echo("key", sections[section].keys[key][index])
    return "text", sections[section].keys[key][index]
  end
end


--filetypes:
--: Pipadoc needs to know about the syntax of line comments of the files it is reading. For this one can
--: register patterns to be matched against the filename together with a list of line comment characters.
--:
--: Pipadoc includes definitions for some common filetypes already.
--:
--: A special case is that when a line comment is defined as an empty string ("") then every line of a file is
--: considered as documentation but no special operations apply. This is used for parsing plaintext documentation
--: files. Which also uses the "PIPADOC:" keyword to enable special operations within text files.
local filetypes = {}


--api:
--: Filetypes
--: ~~~~~~~~~
--:
function filetype_register(names, linecommentseqs, ...) --: `VERBATIM<function%s*(.-%))>`::
  --:     names:::
  --:       a Lua pattern or list of patterns matching filenames
  --:     linecommentseqs:::
  --:       a string or list of strings matching comments of the registered filetype
  --:     ...:::
  --PLANNED: processors to enable for the given filetypes, per filetype processors also supported by --! directives
  --:       (PLANNED FEATURE)
  --:       the remaining arguments are a list of processors which should be enabled for files if this type
  --:
  --: Register a new filetype.
  --:
  --: For example, C and C++ Filetypes are registered like:
  --:
  --:  filetype_register({"%.c$","%.cpp$","%.C$", "%.cxx$", "%.h$"}, {"//", "/*"})
  names = to_table(names)
  linecommentseqs = to_table(linecommentseqs)
  for i=1,#names do
    filetypes[names[i]] = filetypes[names[i]] or {}
    for j=1,#linecommentseqs do
      dbg("register filetype:", names[i], linecommentseqs[j])
      filetypes[names[i]][#filetypes[names[i]]+1] = linecommentseqs[j]
    end
  end
end

function filetype_get(filename)
  assert_type(filename, "string")
  for k,v in pairs(filetypes) do
    if string.match(filename, k) then
      return v,k
    end
  end
end

function filetype_select(line, linecommentseqs)
  for i=1,#linecommentseqs do
    if string.match(line, linecommentseqs[i]) then
      return linecommentseqs[i]
    end
  end
end

--proc:
--: Each line containing a pipadoc comment are passed down through 'processors' which can do
--: additinal actions for manipulating the generated Documentaton. This processors are extendable
--: in Lua.
--:
--api:
--: Processors
--: ~~~~~~~~~~
--:
local processors_available = {}
function processor_register(name, func) --: `VERBATIM<function%s*(.-%))>`::
  --:   name:::
  --:     name of the processor
  --:   func:::
  --:     a function which receives a table of the 'context' parsed from the pipadoc commentline
  --:
  --: Register a new processor. To be called from plugins. Processors need to be enabled
  --: to be used. Some are by default enabled, unless the --nodefaults commmandline option is
  --: used for invoking pipadoc. Some are bound to specific filetypes.
  --:
  --: When plugins register new processors under the same name of an already existing processor
  --: the new processor will overrwrite the old one and become registered.
  --:
  --: The context passed to the function is a table with following entries:
  --:
  --:   pre:::
  --:     'source' part in before the comment character
  --:   section:::
  --:     parsed section name, will be empty in section-blocks to access the current
  --:     section name refer to xref:docvars[]
  --:   op:::
  --:     operator signifying the pipadoc operation
  --:   arg:::
  --:     word right after the operator
  --:   text:::
  --:     the documentation text
  --:
  --: This function is free to modify the context in place or call other api funtions to generate
  --: additional documentation entities.
  dbg("register processor:", name)
  processors_available[assert_type(name, "string")] = assert_type(func, "function")
end

local processors_enabled = {}
--api:
function processor_enable(...) --: `VERBATIM<function%s*(.-%))>`::
  --:     ...:::
  --:       called with an ordered list of processors to enable
  --:
  --: enable the listed processors.
  local procs = {...}
  for i=1,#procs do
    assert_type(procs[i], "string")
    assert_notnil(processors_available[procs[i]])
    processors_enabled[#processors_enabled+1] = procs[i]
  end
end




--op:
--: Operators define the core functionality of pipadoc. They are mandatory in the pibadoc syntax
--: to define a pipadoc comment line. It is possible (but rarely needed) to define additional
--: operators. Operators must be a single punctuation character
local operators = {}
--api:
function operator_register(char, func) --: `VERBATIM<function%s*(.-%))>`::
  --:   char:::
  --:     single punctuation character defining this operator
  --:   func:::
  --:     a function which receives a table of the 'context' parsed from the pipadoc commentline
  --:
  --: Operators drive the main functionality, like invoking the processors and generating the output.
  --:
  --: see xref:processor_register[] and the pipadoc source for a detailed description of the context table
  assert(string.match(char, "^%p$") == char)
  dbg("register operator:", char)
  operators[char] = assert_type(func, 'function')
end

function operator_pattern()
  local pattern=""
  for k in pairs(operators) do
    pattern = pattern..k
  end
  return "["..pattern.."]"
end



--usage:
local options
options = {
  "pipadoc [options...] [inputs..]",  --:   VERBATIM("(.*)")
  "  options are:", --:   VERBATIM("(.*)")

  "    -v, --verbose                    increment verbosity level", --:   VERBATIM("(.*)")
  ["-v"] = "--verbose",
  ["--verbose"] = function () opt_verbose = opt_verbose+1 end,

  "    -q, --quiet                      supresses any messages", --:   VERBATIM("(.*)")
  ["-q"] = "--quiet",
  ["--quiet"] = function () opt_verbose = 0 end,

  "    -d, --debug                      set verbosity to maximum", --:   VERBATIM("(.*)")
  ["-d"] = "--debug",
  ["--debug"] = function () opt_verbose = 3 end,

  "    -h, --help                       show this help", --:   VERBATIM("(.*)")
  ["-h"] = "--help",
  ["--help"] = function ()
    print("usage:")
    for i=1,#options do
                   print(options[i])
                 end
                 os.exit(0)
               end,


  "    -c, --comment <file> <comment>   register a filetype pattern", --:   VERBATIM("(.*)")
  "                                     for files matching a file pattern", --:   VERBATIM("(.*)")
  ["-c"] = "--comment",
  ["--comment"] = function (arg,i)
                    assert(type(arg[i+2]))
                    filetype_register(arg[i+1], arg[i+2])
                    return 2
                  end,


  "    -t, --toplevel <name>            sets 'name' as toplevel node [MAIN]", --:   VERBATIM("(.*)")
  ["-t"] = "--toplevel",
  ["--toplevel"] = function (arg, i)
                assert(type(arg[i+1]))
                opt_toplevel = arg[i+1]
                return 1
              end,

  "    --no-defaults                    disables defaults bindings", --:   VERBATIM("(.*)")
  ["--no-defaults"] = function () opt_nodefaults = true end,


  "    --                               stops parsing the options and treats each", --:   VERBATIM("(.*)")
  "                                     following argument as input file", --:   VERBATIM("(.*)")
  ["--"] = function () args_done=true end,

  --TODO: --alias match pattern --file-as match filename
  --TODO: -o --output
  --TODO: -l --load
  --TODO: --features  show a report which features (using optional lua modules) are available
  --TODO: list-processors
  --TODO: list-operators
  --TODO: list-sections
  --TODO: force filetype variant  foo.lua:.txt
  --TODO: orphans / doublettes
  --TODO: wordwrap
  --TODO: variable replacements
  --TODO: add debug report (warnings/errors) to generated document PIPADOC_LOG section
  --TODO: lineending \n \r\n
  --TODO: wrap at blank/intelligent
  --PLANNED: wordwrap

  "", --:   VERBATIM("(.*)")
  "  inputs are filenames or a '-' which denotes stdin", --:   VERBATIM("(.*)")
}

--local plugins = {}

function parse_args(arg)
  local i = 1
  while i <= #arg do
    while string.match(arg[i], "^%-%a%a+") do
      parse_args {"-"..string.sub(arg[i],2,2)}
      arg[i] = "-"..string.sub(arg[i],3)
    end

    if not options[arg[i]] then
      opt_inputs[#opt_inputs+1] = arg[i]
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

--FIXME: docme why include /* comments

function setup()
  parse_args(arg)

  if not opt_nodefaults then
    --filetypes_def:scons * SCons
    filetype_register("^SConstuct$", "#")

    --filetypes_def:cmake * CMake
    filetype_register({"^CMakeLists.txt$","%.cmake$"}, {"#", "#[["})

    --filetypes_def:c * C, C++, Headerfiles
    filetype_register({"%.c$","%.cpp$","%.C$", "%.cxx$", "%.h$"}, {"//", "/*"})

    --filetypes_def:lua * Lua
    filetype_register({"%.lua$"}, "%-%-")

    --filetypes_def:automake * Autoconf, Automake
    filetype_register({"%.am$", "%.in$", "^configure.ac$"}, {"#", "dnl"})

    --filetypes_def:make * Makefiles
    filetype_register({"^Makefile$", "%.mk$", "%.make$"}, "#")

    --filetypes_def:shell * Shell, Perl, AWK
    filetype_register({"%.sh$", "%.pl$", "%.awk$", }, "#")

    --filetypes_def:prolog * Prolog
    filetype_register({"%.pro$", "%.P$"}, "%")

    --filetypes_def:text * Textfiles, Pipadoc (.pdoc)
    filetype_register({"%.txt$", "%.TXT$", "%.pdoc$", "^-$"}, {"PIPADOC:", ""})

    --filetypes_def:java * Java, C#
    filetype_register({"%.java$", "%.cs$"}, {"//", "/*"})

    --filetypes_def:objective_c * Objective-C
    filetype_register({"%.h$", "%.m$", "%.mm$"}, {"//", "/*"})

    --filetypes_def:python * Python
    filetype_register("%.py$", "#")

    --filetypes_def:visualbasic * Visual Basic
    filetype_register("%.vb$", "'")

    --filetypes_def:php * PHP
    filetype_register("%.php%d?$", {"#", "//", "/*"})
 
    --filetypes_def:javascript * Javascript
    filetype_register("%.js$", "//", "/*")

    --filetypes_def:delphi * Delphi, Pascal
    filetype_register({"%.p$", "%.pp$", "^%.pas$"}, {"//", "{", "(*"})

    --filetypes_def:ruby * Ruby
    filetype_register("%.rb$", "#")

    --filetypes_def:sql * SQL
    filetype_register({"%.sql$", "%.SQL$"}, {"#", "--", "/*"})
  end

  --TODO: DOCME
  processor_register(
    "docvars",
    function (context)
      assert_type(context, "table")

      --FIXME: prevent re-recursive expansion
      --FIXME: double percent signs escape to a single percent sign
      --PLANNED: more general macro and string replacement facility, possibly even functions
      repeat
        local var = string.match(context.text, "%%(%a[%w_]*)%%")
        if var and docvars[var] then
          context.text = string.gsub(context.text, "%%"..var.."%%", docvars[var])
        end
      until not var
    end
  )

  --TODO: docme
  processor_register(
    "verbatim",
    function (context)
      assert_type(context, "table")

      repeat
        local pattern = string.match(context.text, "VERBATIM(%b())")
        pattern = pattern or string.match(context.text, "VERBATIM(%b[])")
        pattern = pattern or string.match(context.text, "VERBATIM(%b{})")
        pattern = pattern or string.match(context.text, "VERBATIM(%b<>)")
        if pattern then
          local escaped = string.gsub(pattern, "%p", "%%%1")
          local prepart = string.match(context.pre, string.sub(pattern, 2, -2))
          context.text = string.gsub(context.text, "VERBATIM"..escaped, prepart or "")
        end
      until not pattern

      context.text = string.gsub(context.text, "VERBATIM", context.pre)
    end
  )

  processor_register(
    "asciidoc",
    function (context)
      assert_type(context, "table")

      --PLANNED: make each feature switchable, options to processor

      -- insert source references as asciidoc comments
      if context.section ~= "" then
        local _, value = section_get(context.section, context.key)
        if value and value ~= "" then
          section_append(context.section, context.key, "text", "")
        end
        section_append(context.section, context.key, "text", "// "..docvars.FILE..":"..docvars.LINE.." //")
      end

    end
  )

  processor_register(
    "annotations",
    function (context)
      assert_type(context, "table")

      -- insert source references as asciidoc comments
      if context.section == "TODO" or context.section == "FIXME" or context.section == "PLANNED" then
        context.text = ""..docvars.FILE..":"..docvars.LINE.."::"..docvars.NL.."  "..context.text
      end

    end
  )


  --[[[  dd
  operator_register(
    "!",
    function (arg, text)
      -- DIRECTIVE load unused reuse
    end)
  --]]





  --op_def:
  --:   `:` ::
  --:     The documentation operator. Defines normal documentation text. Each pipadoc comment using the `:`
  --:     operator is processed as potential documentation. First all enabled 'processors' are run over it and
  --:     finally the text is appended to the current section(/key)
  operator_register(
    ":",
    function (context)
      -- for oneline sections
      local section_bak

      if #context.section > 0 then
        if #context.text > 0 then
          section_bak = docvars.SECTION
        end
        docvars.SECTION = context.section
      end

      for i=1,#processors_enabled do
        processors_available[processors_enabled[i]](context)
      end

      if #context.text > 0 or #context.section == 0 then
        section_append(docvars.SECTION, context.arg, "text", context.text)
      end

      if section_bak then
        docvars.SECTION = section_bak
      end
    end
  )


  --op_def:
  --:   `=` ::
  --:     Section paste operator. Takes a section name as argument and will paste that section in place.
  operator_register(
    "=",
    function (context)
      local section = #context.section > 0 and context.section or docvars.SECTION

      --PLANNED: how to use context.text?
      if #context.arg > 0 then
        section_append(section, nil, "include", context.arg)
      else
        warn("include argument missing:")
      end
    end
  )


  --op_def:
  --:   `@` ::
  --:     Alphabetic Sorted Section paste operator. Takes a section name as argument and will paste
  --:     section text with keys alphabetically sorted in place.
  operator_register(
    "@",
    function (context)
      local section = #context.section > 0 and context.section or docvars.SECTION

      if #context.arg > 0 then
        section_append(section, nil, "sort", "alphabetic "..context.arg.." "..context.text)
      else
        warn("sort section missing:")
      end
    end
  )

  --TODO: op #
  
  --TODO: plugins
  --   for plugin in pairs(plugins) do
  --      load_plugin(plugin)
  --   end
  



  if not opt_nodefaults then
    processor_enable("docvars", "verbatim", "annotations", "asciidoc")
  end


end


function process_line (line, comment)
  local context = {}

  -- special case for plaintext files
  if comment ~= "" then
    context.pre, context.section, context.op, context.arg, context.text =
      string.match(line,"^(.-)"..comment.."([%w_.]*)("..operator_pattern()..")([%w_.]*)%s?(.*)$")
  else
    context.pre = ""
    context.section = ""
    context.op = ":"
    context.arg = ""
    context.text = line
  end

  if context.op then
    dbg("pre:", context.pre, "section:", context.section, "op:", context.op, "arg:", context.arg, "text:", context.text)
    if operators[context.op] then
      dbg("op:", context.op)
      while operators[context.op] do
        context.op = operators[context.op]
      end
      context.op(context)
    else
      warn("unknown operator:", context.op)
    end
  end
end

function process_file(file)
  local linecommentseqs, pattern = filetype_get(file)
  if not linecommentseqs then
    warn("unknown file type:", file)
    return
  end

  --docvars:section   `SECTION`::
  --docvars:sectionb      stores the current section name
  docvars.SECTION = string.match(file, "%.*([^.]*)")

  local fh
  if file == '-' then
    docvars.FILE = "<stdin>"
    fh = io.stdin
  else
    fh = io.open(file)
    if not fh then
      warn("file not found:", file)
      return
    end
    docvars.FILE = file
  end

  docvars.LINE = 0
  dbg("section:", docvars.SECTION)

  for line in fh:lines() do
    docvars.LINE = docvars.LINE+1
    dbg("line:", line)
    local comment = filetype_select(line, linecommentseqs)
    if comment then
      process_line(line, comment)
    end
  end
  fh:close()
end

function process_inputs()
  for i=1,#opt_inputs do
    --TODO: globbing if no such file exists
    process_file(opt_inputs[i])
  end
end

local sortfuncs = {
  numeric = function (a,b)
    return (tonumber(a) or 0) < (tonumber(b) or 0)
  end,
  alphabetic = function (a,b)
    return tostring(a) < tostring(b)
  end,
}


function generate_output_sorted(order, which, opt)
  dbg("generate_output_sorted:", order, which, opt)
  local section = sections[which].keys

  if section ~= nil then
    local oldfile=docvars.FILE
    docvars.FILE='<output>:'..which

    local sorted = {}

    for k in pairs(section) do
      table.insert(sorted, k)
    end

    table.sort(sorted, sortfuncs[order])

    for i=1,#sorted do
      docvars.LINE=sorted[i]
      for j=1,#section[sorted[i]] do
        io.write(section[sorted[i]][j], '\n')
      end
    end
    docvars.FILE=oldfile
  else
    warn("no section named:", which)
  end
end



function generate_output(which)
  dbg("generate_output:", which)
  local section = sections[which]

  if section ~= nil then
    local oldfile=docvars.FILE
    docvars.FILE='<output>:'..which
    for i=1,#section do
      docvars.LINE=i
      dbg("generate", section[i].action, section[i].text)
      --:TODO docme actions
      if section[i].action == "text" then
        io.write(section[i].text, '\n')
      elseif section[i].action == "include" then
        --:TODO recursion detection
        generate_output(section[i].text)
      elseif section[i].action == "sort" then
        generate_output_sorted(string.match(section[i].text, "^([%w_]*) ?([%w_]*) ?(.*)"))
      end
    end
    docvars.FILE=oldfile
  else
    warn("no section named:", which)
  end
end

setup()
process_inputs()

docvars.FILE = "<output>"
docvars.LINE = 0

generate_output(opt_toplevel)
-- orphans / doublettes



--MAIN:
--: pipadoc - Documentation extractor
--: =================================
--: Christian Thaeter <ct@pipapo.org>
--:
--: Embedding documentation in program source files often yields the problem that the
--: structure of a program is not the optimal structure for the associated documentation.
--: Still there are many good reasons to maintain documentation together with the source right within
--: the code which defines the documented functionality. Pipadoc addresses this problem by extracting
--: special comments out of a source file and let one define rules how to bring the
--: documentation into proper order.
--:
--: Pipadoc only extracts and reorders the text from it special comments, it never ever looks at the
--: sourcecode or the text it extracts.
--:
--: This is somewhat similar to ``literate Programming'' but it puts the emphasis back to the code.
--: There is no need to extract the source from a literate source and in contrast to ``Literate Programming''
--: the order of source and text is defined by the programmer and programming language constraints.
--:
--: Pipadoc is programming language and documentation system agnostic, all it requires is that
--: the programming language has some form of comments starting with a defined character sequence
--: and spaning to the end of the line.
--:
--: Installation
--: ------------
--:
--: 'pipadoc' comes as single lua source file `pipadoc.lua` which is portable among most Lua versions
--: (PUC Lua 5.1, 5.2, 5.3 and luajit). It ships with a `pipadoc.install` shell script which figures a
--: suitable Lua version out and installs `pipadoc.lua` as `pipadoc` in a given directory or the current
--: directory by default.
--:
--: There are different ways how this can be used in a project:
--:
--: - One can rely on a pipadoc installed in $PATH and just call that from the build toolchain
--: - When a installed Lua version is known from the build toolchain one can include the `pipadoc.lua`
--:   into the project and call it with the known Lua interpreter.
--: - One can ship the `pipadoc.lua` and `pipadoc.install` and do a local install in the build
--:   directory and use this pipadoc thereafter
--:
--: Usage
--: -----
--:
--=usage
--:
--: Basic concepts
--: --------------
--:
--: Pipadoc is controlled by special line comments. This is choosen because the most common denominator
--: between almost all programming languages is that they have some form of 'line comment', that is some
--: character sequence which defines the rest of the line as comment.
--:
--: This line comments are enhanced by a simple syntax to make them pipadoc comments. Basically the comment
--: character followed directly (without any extra space character) by some definition (see below) becomes
--: a pipadoc comment.
--:
--: Pipadoc Syntax
--: ~~~~~~~~~~~~~~
--:
--: Any 'linecomment' of the programming language directly (without spaces) followed by a optional
--: alphanumeric section name, followed by an operator, followed by an optional argument and then the
--: documentaton text. Only lines qualitfy this syntax are processed as pipapdoc documentation.
--:
--: The formal syntax looks like:
--:
--:   pipadoc = [source] <linecomment> [section] <operator> [arg] [..space.. [documentation_text]]
--:
--:   source = ..any sourcecode text..
--:
--:   linecomment = ..the linecomment sequence choosen by the filetype..
--:
--:   section = ..alphanumeric text including underscore and dots, but without spaces..
--:
--:   operator = [:=@#] by default, one of the defined operators
--:
--:   arg = ..alphanumeric text including underscore and dots, but without spaces..
--:
--:   documentation_text = ..rest of the line, freeform text..
--:
--:
--: It is possible to extend pipadoc with plugins which provide new operators or new processors.
--:
--: Documentation lines are proccessed according to their operator.
--:
--TODO: docme oneline vs block, default section name, MAIN section
--TODO: note that literal strings are not special
--:
--:
--: Sections
--: --------
--:
--=sections
--:
--: Filetypes
--: ---------
--:
--=filetypes
--:
--: pipadoc has already support for following languages builtin
--: ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
--:
--@filetypes_def
--:
--: Processors
--: ----------
--:
--=proc
--:
--: Operators
--: ---------
--:
--=op
--:
--: Built in default operators
--: ~~~~~~~~~~~~~~~~~~~~~~~~~~
--:
--=op_def
--:
--: Documentation Variables
--: -----------------------
--:
--: The 'docvars' Lua table holds key/value pairs of variables with the global state
--: of pipadoc. These can be used by the core and plugins in various ways. Debugging
--: for example prints the FILE:LINE processed and there is a processor to substitute
--: them in the documentation text. The user can set arbitary docvars from commandline.
--:
--: Predefined docvars
--: ~~~~~~~~~~~~~~~~~~
--:
--@docvars
--:
--:

--:
--:
--:
--:
--:
--:
--:
--:
--:
--:

--:
--: TODO
--: ----
--:
--=TODO
--:
--:
--: PLANNED
--: -------
--:
--=PLANNED
--:
--: FIXME
--: -----
--:
--=FIXME
--:

--: EXAMPLE
--=ex
--@ex
--:
--: Programming API for extensions
--: ------------------------------
--:
--: Some pipadoc lua functions are documented here to be used from plugins.
--:
--=api

--TODO: history

--LICENSE:
--: License Explanation
--: ~~~~~~~~~~~~~~~~~~~
--:
--: The License (GPL) only applies to pipadoc and any derivative work. The purpose of pipadoc
--: is to extract documentation from other files, this does not imply that these source files
--: from which the documentation is extracted need to be licensed under the GPL, neither does
--: this imply that the extracted documentaton need to be licensed under the GPL.
--: Using pipadoc for propietary software poses no problems about the Licenensing terms of
--: this software.
--:
--: The GPL applies when you distribute pipadoc itself, in original or modified form. Since
--: pipadoc is written in Lua you already distribute its source as well, which makes this
--: distribution naturally with the GPL.
--:
--: Nevertheless, when you make any improvements to pipadoc please consider to contact
--: Christian Thäter <ct@pipapo.org> for including them into the mainline.


--ex:
--: example
--:
--ex:a inline1
--ex:a inline2
--ex:b inline3
--: back to ex
--:
--ex:b
--: not inline in ex.b
--:
--: back to ex
--:
--:c inline ex.c
--:
--:
--:
--foo:
  --: dokumentiert foo

  --gloss:example example im glossary

  --=gloss include

  --@gloss filter/pattern/options  include keys alpahbetically
  --#gloss compare/match/range  include keys numerically

  --code: this is VERBATIM(pattern)
  --code: this is VERBATIM


--TODO: asciidoc //source:line// comments like old pipadoc
--TODO: integrate old pipadoc.txt documentation

