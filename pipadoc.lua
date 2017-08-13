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
-------------------------------------------------------------------------------------------------
--PLANNED: include operator, add a file to the processing list
--PLANNED: merge lines, '+' operator?
--+        like this, note about indentation, no newline
--PLANNED: Version check for documents \{VERSION 2\} ...
--PLANNED: --disable-strsubst option
--PLANNED: merge sections for sorting --#foo+bar+baz or something like this

DOCVARS = {
  --DOCVARS:nl {DVARDEF NL}
  --DOCVARS:nl   The line-break character sequence, defaults to '\n' and
  --DOCVARS:nl   can be changed with the '--define' command-line option.
  NL = "\n",

  --DOCVARS:nil {DVARDEF NIL}
  --DOCVARS:nil   Expands to an empty string.
  NIL = "",

  --DOCVARS:markup {DVARDEF MARKUP}
  --DOCVARS:markup   The markup syntax (--markup option). This information only used by pipadoc
  --DOCVARS:markup   for selecting postprocessors. Other user defined extensions may use it as
  --DOCVARS:markup   well.
  MARKUP = "text",
}

DOCVARS_POST = {}


local CONTEXT = setmetatable (
  {
    --context:file {DVARDEF FILE}
    --context:file   The file or section name currently processed or some special annotation
    --context:file   in angle brackets (eg '<startup>') on other processing phases
    --context:line {DVARDEF LINE}
    --context:line   Current line number of input or section, or indexing key
    --context:line   Lines start at 1
    FILE = "<startup>"
  }, {__index = DOCVARS})


--TODO: DOCME
function set_gcontext(file, line)
  assert_type(file, 'string')
  CONTEXT.FILE = file
  CONTEXT.LINE = line
end

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
    context = context or CONTEXT
    printerr(context.FILE..":"..(context.LINE and context.LINE..":" or ""), ...)
  end
end


--api_logging:
--:
--: Logging Progress and Errors
--: ~~~~~~~~~~~~~~~~~~~~~~~~~~~
--:
--: Functions for to log progress and report errors. All this functions take a variable argument
--: list. Any argument passed to them will be converted to a string and printed to stderr when
--: the verbosity level is high enough.
--:
function warn(context,...) --: report a important but non fatal failure
  printlvl(context,1, ...)
end

--TODO: info is not used
function info(context,...) --: report normal progress
  printlvl(context,2, ...)
end

function dbg(context,...) --: show debugging information
  printlvl(context,3, ...)
end

function trace(context,...) --: show more detailed progress information
  printlvl(context,4, ...)
end


function die(context, ...) --: report a fatal error and exit the program
  context = context or CONTEXT
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



--api_load:
--:
--: Dependencies
--: ~~~~~~~~~~~~
--:
--: 'pipadoc' does not depend on any external Lua libraries. The intention is to, by default,
--: make documentation build able on minimal target systems. Nevertheless modules can be loaded
--: optionally to augment pipadocs behavior and provide extra features. Plugin-writers should
--: try to adhere to this practice if possible and use the 'request()' function instead the Lua
--: 'require()'. Falling back to simpler but usable functionality when some library is not
--: available or call 'die()' when a reasonable fallback won't be available.
--:
--: Pipadoc already calls 'request "luarocks.loader"' to make rocks modules available when
--: installed.
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


--api_typecheck:
--:
--: Type Checks
--: ~~~~~~~~~~~
--:
--: Wrappers around 'assert' to check externally supplied data. On success 'var' will be returned
--: otherwise an assertion error is raised.
--:

--PLANNED: assert_type(var, ...) list of strings
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


--api_strsubst:
--:
--: String Substitution
--: ~~~~~~~~~~~~~~~~~~~
--:
--: Documentation-text is be passed to the strsubst() function which recursively substitutes
--: expressions within curly braces. The substitutions are taken from the passed context.
--: Strings are replaced, functions become evaluated, everything else is translated with Luas
--: 'tostring()' function.
--:
--: The Names for substitituions must start with an alphabetic character or underline and can
--: be followed by alphanumeric characters or underlines. It may be followed with a space and --: an optional argument string which gets passed to functions or retained verbatim on
--: everyting else.
--:
--: Curly braces, can be escaped with backslashes or backtick characters. These
--: characters can be escaped by themself.
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

local escapes = {
  ["\\"] = "{__BACKSLASH__}",
  ["`"] = "{__BACKTICK__}",
  ["{"] = "{__BRACEOPEN__}",
  ["}"] = "{__BRACECLOSE__}",
}

local escapes_back = table_inverse(escapes)


--api_strsubst:
function strsubst (context, str, escapes, escapes_back) --: substitute text in
  --TODO: doc parameters
  trace (context, "strsubst:", str)
  maybe_type (context, "table")
  assert_type (str, "string")

  context = context or CONTEXT
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

                      -- recursively dereferrence names when braced
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
                          --cwarn:  cyclic substititution.
                        end
                      else
                        if escapes_back and not ret:match "^{__.*__}$" then
                          warn (context, "strsubst no expansion", capture)  --cwarn: <STRING> ::
                          --cwarn:  no substitution defined.
                        end
                      end

                      return ret
                    end
    )
  end

  if escapes then
    str =  str:gsub("[`\\]([{}\\])", escapes)
  end

  str = strsubst_intern(str)

  if escapes_back then
    str = str:gsub("%b{}", escapes_back)
  end

  return str
end

local function pattern_escape (p)
  return (p:gsub("%W", "%%%1"))
end

--sections:
--: Text in pipadoc is appended to named 'sections'. Text can be associated with some
--: alphanumeric key under that section. This enables later sorting for indexes and glossaries.
--:
--: Sections can be one line or span a block of lines.
--:
--: One line sections are defined when a section and maybe a key is followed by documentation
--: text. Block sections start with the section definition but no documentation text on the same
--: line. A block stays active until the next block section definition. One line doctext can be
--: interleaved into Blocks.
--:
--: When no section is set in a file, then the block section name defaults to the files name up,
--: but excluding to the first dot.
--:
--: Sections are later brought into the desired order by pasting them into a 'toplevel' section.
--: This default name for the 'toplevel' section is'MAIN'.
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
--: itself using 'asciidoc' as markup. Refer to it's source to see a bigger example about
--: how it is done.
--:
local sections = {}
local sections_usecnt = {}
local sections_keys_usecnt = {}

--api_sections:
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
  trace(context, "append:", section, key, context.TEXT)
  sections[section] = sections[section] or {keys = {}}
  if key and #key > 0 then
    sections[section].keys[key] = sections[section].keys[key] or {}
    table.insert(sections[section].keys[key], context)
  else
    table.insert(sections[section], context)
  end
end

--filetypes:
--: Pipadoc needs (only) to know about the syntax of line comments of the files it is reading.
--: For this patterns are registered to be matched against the file name together with a list of
--: line comment characters.
--:
--: There are many definitions included for common filetypes already. For languages which
--: support block comments the opening (but not the closing) commenting characters are
--: registered as well. This allows one to define section blocks right away. Using the
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
--: for plaintext documentation files. Which also uses the "PIPADOC:" keyword to enable special
--: operations within text files.
--:
--: New uncommon filetypes can be added from a config file with 'filetype_register()'  or with
--: the '--register' commandline option.
--:
local filetypes = {}

--api_filetypes:
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
    filetypes[filep[i]] = filetypes[filep[i]] or {language = name}
    for j=1,#linecommentseqs do
      dbg(nil, "register filetype:", name, filep[i], pattern_escape(linecommentseqs[j]))
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

local function comment_select (line, filetype)
  for i=1,#filetype do
    if string.match(line, filetype[i]) then
      return filetype[i]
    end
  end
end


local preprocessors = {}
--api_preproc:
--:
--: Preprocessors
--: ~~~~~~~~~~~~~
--:
--: One can register multiple preprocessors for different filetypes. A preprocessor can modify
--: the line prior it is parsed and further processed. By default pipadoc has no preprocessors
--: defined. The user may define these in a config file. See the <<_configuration_file,
--: 'pipadoc_config.lua'>> which ships with the pipadoc distribution.
--:
function preprocessor_register (langpat, preprocess) --: register a preprocessor
  --:   langpat:::
  --:     Register preprocessor to all filetypes whose mnemonic matches 'langpat'.
  --:   preprocess:::
  --:     The preprocesor to register. Can be one of:
  --:     `function (line) ... end` ::::
  --:       Takes a string (the source line) and shall return the preprocessed line or 'nil' to
  --:       drop the line.
  --:     +\{pattern, repl [, n]\}+ ::::
  --:       Generates a function calling 'string.gsub(pattern, repl [, n])' for preprocessing.
  --:
  --PLANNED: langpat as list of patterns
  assert_type (langpat, "string")
  dbg (nil, "register preprocessor:", langpat, preprocess)

  if type (preprocess) == "table" then
    preprocess = function (str)
      return str:gsub (preprocess, preprocess[1], preprocess[2], preprocess[3])
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



local postprocessors = {}
--api_postproc:
--:
--: Postprocessors
--: ~~~~~~~~~~~~~~
--: Postprocessors run at output generation time. They are registered per markup types.
--: Processors are called in order of their definition.
--:
function postprocessor_register (markuppat, postprocess) --: register a postprocessor
  --:   markuppat:::
  --:     Register postprocessor to all markups whose name matche 'markuppat'.
  --:   postprocess:::
  --:     The postprocesor to register. Can be one of:
  --:     `function (line) ... end` ::::
  --:       Takes a string (the source line) and shall return the postprocessed line or 'nil' to
  --:       drop the line.
  --:     +\{pattern, repl [, n]\}+ ::::
  --:       Generates a function calling 'string.gsub(pattern, repl [, n])' for postprocessing.
  --:
  --PLANNED: markuppat as list of patterns
  assert_type (markuppat, "string")
  dbg (nil, "register postprocessor:", markuppat, postprocess)

  if type (postprocess) == "table" then
    postprocess = function (str)
      return str:gsub (postprocess, postprocess[1], postprocess[2], postprocess[3])
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
    if DOCVARS.MARKUP:match(ppdesc.pattern) then
      trace (nil, "add postprocessor for:", DOCVARS.MARKUP, ppdesc.postprocessor)
      table.insert(active_postprocessors, ppdesc.postprocessor)
    end
  end
end

--PLANNNED: wrap pcall for debugging purpose
local function postprocessors_run (context)
  local textin = context.TEXT
  for i=1,#active_postprocessors do
    local ok, msg = pcall(active_postprocessors[i], context)
    if not ok then
      warn(context, "postprocessor failed:", msg) --cwarn: <STRING> ::
      --cwarn:  error in postprocessor.
    end
    if not context.TEXT then
      break
    end
  end

  if context.TEXT then
    context.TEXT = strsubst(context, context.TEXT, nil, escapes_back)
  end

  if context.TEXT ~= textin then
    trace (context, "postprocess:", textin, "->",  context.TEXT)
  end
end

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
--: ~~~~~~~~~
--:
--: Operators have 2 functions associated. The first one is the processing function which
--: defines how a documentation comment gets stored. The second one is the generator function
--: which will emits the documentation.
--:
function operator_register(char, procfunc, genfunc) --: Register a new operator
  --:   char:::
  --:     single punctuation character defining this operator.
  --:   procfunc +function(context)+:::
  --:     a function which receives a table of the 'context' parsed from the pipadoc comment
  --:     line. It is responsible for storing the context under the approbiate section/key and
  --:     keep a state for further processing.
  --:   genfunc +function(context)+:::
  --:     the a function generating the output from given context.
  --:
  assert(string.match(char, "^%p$") == char)
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

--api_various:
function add_inputfile(filename) --: Add a 'filename' to the list of files to process
  assert_type(filename, "string")
  opt_inputs[#opt_inputs+1] = filename
end

function register_alias(from, to) --: Register a new alias
  assert_type(from, "string")
  assert_type(to, "string")
  dbg(nil, "register alias:", from, "->", to)
  opt_aliases[#opt_aliases+1] = {from, to}
end


local function check_args(arg, n)
  assert(#arg >= n, "missing arg: "..arg[n-1])
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
  "                        set verbosity to maximum", --:  <STRING>
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
  "                        disables default filetypes and configfile", --:  <STRING>
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
    DOCVARS.MARKUP = arg[i+1]
    dbg(nil, "markup:", DOCVARS.MARKUP)
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
  "                         --a '(.*)%.install' '%1.sh'", --:  <STRING>
  ["-a"] = "--alias",
  ["--alias"] = function (arg, i)
    check_args(arg, i+2)
    register_alias (arg[i+1], arg[i+2])
    return 2
  end,
  "", --:  <STRING>

  --PLANNED: define for DOCVARS_POST --define-post -P
  "    -D, --define <name>[=<value>]", --:  <STRING>
  "                        define a DOCVAR to value or 'true'", --:  <STRING>
  "    -D, --define -<name>", --:  <STRING>
  "                        undefine a DOCVAR", --:  <STRING>
  ["-D"] = "--define",
  ["--define"] = function (arg,i)
    check_args(arg, i+1)
    local key,has_value,value = arg[i+1]:match("^([%w_]+)(=?)(.*)")
    local undef = arg[i+1]:match("^[-]([%w_]+)")
    if undef then
      dbg(nil, "undef:", undef)
      DOCVARS[undef] = nil
    elseif key then
      if has_value == "" then
        value = 'true'
      end
      dbg(nil, "define:", key, value)
      DOCVARS[key] = value
    end
    return 1
  end,
  "", --:  <STRING>

  -- intentionally here undocumented, only works in development tree
  ["--make-doc"] = function (arg, i)
    os.execute [[
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
    --PLANNED: run univerally
    os.execute [[
        lua pipadoc.lua -m asciidoc -D GIT -t ISSUES pipadoc.lua pipadoc_config.lua
    ]]
  end,

  "    --", --:  <STRING>
  "                        stops parsing the options and treats each", --:  <STRING>
  "                        following argument as input file", --:  <STRING>
  ["--"] = function () args_done=true end,

  --PLANNED: --features  show a report which features (using optional Lua modules) are available
  --PLANNED: list-sections
  --PLANNED: eat (double, triple, ..) empty lines (do this in a postprocessor)
  --PLANNED: add debug report (warnings/errors) to generated document PIPADOC_LOG section
  --PLANNED: wrap at blank/intelligent
  --PLANNED: wordwrap
  --PLANNED: some flags get defaults from the config file
  --PLANNED: source indent with prettyprinting --indent columns
  --PLANNED: strip option (pre/postprocessor?) to remove all pipadoc

  "", --:  <STRING>
  "  inputs are file names or a '-' which indicates standard input", --:  <STRING>
}

function usage()
  print("usage:")
  for i=1,#options do
    print(options[i])
  end
  os.exit(0)
end


function parse_args(arg)
  set_gcontext "<parse_args>"

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
        die(nil, "optarg error")
      end
    end
    i = i+1
  end
end

-- store state for block comments
local block_section
local block_arg


local function builtin_filetypes()
  --PLANNED: write preprocessor macro to expand filetype_register() as documentation
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
  parse_args(arg)
  set_gcontext "<setup>"

  request "luarocks.loader"
  --PLANNED: for pattern matching etc
  --lfs = request "lfs"
  --posix = request "posix"

  do
    local time = os.time()
    local date = os.date ("*t", time)
    --DOCVARS:date {DVARDEF YEAR, MONTH, DAY, HOUR, MINUTE}
    --DOCVARS:date   Current date information
    DOCVARS.YEAR = date.year
    DOCVARS.MONTH = date.month
    DOCVARS.DAY = date.day
    DOCVARS.HOUR = date.hour
    DOCVARS.MINUTE = date.min

    --PLANNED: locale support for dates
    --DOCVARS:date {DVARDEF DAYNAME, MONTHNAME}
    --DOCVARS:date   The name of the day of week or month
    DOCVARS.DAYNAME = os.date ("%A", time)
    DOCVARS.MONTHNAME = os.date ("%B", time)

    --DOCVARS:date {DVARDEF DATE}
    --DOCVARS:date   Current date in YEAR/MONTH/DAY format
    DOCVARS.DATE = date.year.."/"..date.month.."/"..date.day
    --DOCVARS:date {DVARDEF LOCALDATE}
    --DOCVARS:date   Current date in current locale format
    DOCVARS.LOCALDATE = os.date ("%c", time)
  end

  if not opt_nodefaults then
    --PLANNED: read style file like a config, lower priority, different paths (./ /etc/ ~/ ...)
    --PLANNED: for each language/markup (pipadoc_ascidoc.lua) etc
    builtin_filetypes()
    if opt_config then
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
      if context.TEXT ~= "" and (context.SECTION or context.ARG) then
        --oneline
        context.SECTION = context.SECTION or block_section
        context.ARG = context.ARG or block_arg
        context.TEXT = strsubst(context, context.TEXT, escapes)
        section_append(context.SECTION, context.ARG, context)
      elseif context.TEXT == "" and (context.SECTION or context.ARG) then
        --block head
        block_section = context.SECTION or block_section
        block_arg = context.ARG -- or block_arg
      else
        --block cont
        context.SECTION = context.SECTION or block_section
        context.ARG = context.ARG or block_arg
        context.TEXT = strsubst(context, context.TEXT, escapes)
        section_append(context.SECTION, context.ARG, context)
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
      return generate_output(context.ARG, output)
    end
  )


  local function sortprocess(context)
    context.SECTION = context.SECTION or block_section

    if context.ARG and #context.ARG > 0 then
      section_append(context.SECTION, nil, context)
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

  preprocessors_attach ()
  postprocessors_attach ()
end

local function process_line (context, comment)
  --context:
  --:pre {DVARDEF PRE}
  --:pre   Contains the sourcecode in font of the line comment.
  --:comment {DVARDEF COMMENT}
  --:comment   Character sequence which is used as line comment.
  --:section {DVARDEF SECTION}
  --:section   Section where the documentation should appear.
  --:op {DVARDEF OP}
  --:op   Single punctuation operator defining how to process this line.
  --:arg {DVARDEF ARG}
  --:arg   Optional argument to the operator. This can be the sort key
  --:arg   (alphabetic or numeric) or another section name for pasting.
  --:text {DVARDEF TEXT}
  --:text  The actual Documentation Text.

  -- special case for plaintext files
  if comment == "" then
    context.PRE, context.COMMENT, context.SECTION, context.OP, context.ARG, context.TEXT =
      "", " ", nil, ":", nil, context.SOURCE
  else
    local pattern = "^(.-)("..comment..")([%w_.]*)("..operator_pattern()..")([%w_.]*)%s?(.*)$"
    dbg(context, "pattern:", pattern)
    context.PRE, context.COMMENT, context.SECTION, context.OP, context.ARG, context.TEXT =
      string.match(context.SOURCE, pattern)
    context.SECTION = to_text(context.SECTION)
    context.ARG = to_text(context.ARG)
  end

  local op = context.OP
  if op then
    dbg(context, "pre:", context.PRE, "section:", context.SECTION, "op:", op, "arg:", context.ARG, "text:", context.TEXT)

    context.SOURCE = nil

    local ok,err = pcall(procfuncs[op], context)
    if not ok then
      warn (context, "operator processing failed", op, err) --cwarn: <STRING> ::
      --cwarn:  error executing a operators processor.
    end
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

--TODO: DOCME
function make_context(parent, new)
  return setmetatable(new or {}, {__index = parent})
end



local function process_file(file)
  -- filecontext is a partial context storing data
  -- of the current file processed
  local filecontext = make_context(DOCVARS, {
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
    --cwarn:  The type of the given file was not recongized (see <<_usage,'--register'>> option).
    return
  end

  block_section = filecontext.FILE:match("[^./]+%f[.%z]")
  dbg(filecontext, "section:", block_section)

  filecontext.LANGUAGE = filetype.language
  dbg(filecontext, "language:", filecontext.LANGUAGE)

  filecontext.COMMENT = filetype[1] --TODO: docme first one already set for construction in pp

  local lineno = 0
  for line in fh:lines() do
    lineno = lineno + 1
    trace(filecontext, "input:", lineno)

    --context:
    --:source {DVARDEF SOURCE}
    --:source   The line read from the input file, used for preprocessing and will be erased
    --:source   afterward preprocessing is done.
    local context = make_context(filecontext, {
                                   LINE = lineno,
                                   SOURCE = line,
    })

    local preprocessors = filetype.preprocessors
    if preprocessors then
      for i=1,#preprocessors do
        local oldsource = context.SOURCE
        local ok,msg = pcall(preprocessors[i], context)
        if not ok then
          warn(context, "preprocessor failed:", msg) --cwarn: <STRING> ::
          --cwarn:  error in preprocessor.
          --PLANNED: preprocessors may expand to multiple lines? return table
        elseif context.SOURCE ~= oldsource then
          trace(context, "preprocessed:", oldsource, "->", context.SOURCE)
        end
        if not context.SOURCE then
          break
        end
      end
    end

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


local sofar_rec={}

function generate_output(which, output)
  set_gcontext "<output>"
  dbg(nil, "generate_output:", which)
  local section = sections[which]

  if section ~= nil then
    if sofar_rec[which] then
      warn(nil, "recursive paste:",which) --cwarn: <STRING> ::
      --cwarn:  Pasted sections (see <<_built_in_operators,paste operator>>) can not recursively
      --cwarn:  include themself.
      return ""
    end

    if #section == 0 then
      warn(nil, "section is empty:",which)
      return ""
    end
    sofar_rec[which] = true
    sections_usecnt[which] = (sections_usecnt[which] or 0) + 1

    for i=1,#section do
      CONTEXT.LINE=i
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
    sofar_rec[which] = nil
  else
    warn(nil, "no section named:", which)
  end
end


--PLANNED: some way to hint the checker to supress these warnings
function report_orphan_doubletes()
  local orphan = {FILE = "<orphan>"}
  local doublette = {FILE = "<doublette>"}
  for k,v in pairs(sections_usecnt) do
    if v == 0 then
      warn(orphan, "section unused:", k) --cwarn: <STRING> ::
      --cwarn:  The printed section was not used. This might be intentional when generating
      --cwarn:  only partial outputs.
    elseif v > 1 then
      warn(doublette, "section multiple times used:", k, v) --cwarn: <STRING> ::
      --cwarn:  Section was pasted multiple times in the output.
    end
  end

  for k,v in pairs(sections_keys_usecnt) do
    if v == 0 then
      warn(orphan, "section w/ keys unused:", k) --cwarn: <STRING> ::
      --cwarn:  Section with keys (numeric or alphabetic) was not used.
    elseif v > 1 then
      warn(doublette, "section w/ keys multiple times used:", k, v) --cwarn: <STRING> ::
      --cwarn:  Section was used multiple times in the output ('@', '$' or '#' operator).
    end
  end
end

function cmp_files(aname,bname)
  local a_fd = io.open(aname)
  local b_fd = io.open(bname)

  local a,b = true,false

  if a_fd and b_fd then
    a = a_fd:read("*a")
    b = b_fd:read("*a")
  end

  if a_fd then a_fd:close () end
  if b_fd then b_fd:close () end

  return a == b
end

do
  setup()
  process_inputs()

  -- free memory
  --PLANNED: memory profile whats faster?
  collectgarbage()

  local output = {}

  generate_output(opt_toplevel, output)

  local outfd = io.stdout
  local tmpfile

  if opt_output then
    local dir,name = opt_output:match("(.-)([^/]*)$")
    tmpfile = dir.."."..name
    outfd = io.open(tmpfile, "w+")
    --FIXME: -o /dev/null ... handle error when tmpfile cant be opened
  end


  set_gcontext "<postprocessing>"
  section_append = function () die(nil, "section_append() not available after generating output") end

  --activate DOCVARS_POST for postprocessing
  setmetatable (DOCVARS, {__index = DOCVARS_POST})

  for i=1,#output do
    postprocessors_run(output[i])
    if output[i].TEXT then
      outfd:write(output[i].TEXT, DOCVARS.NL)
    end
  end
  -- free memory
  sections = nil
  output = nil
  collectgarbage()

  if opt_output then
    outfd:close()

    if not cmp_files(tmpfile, opt_output) then
      dbg(nil, "rename:",tmpfile, opt_output)
      os.rename(tmpfile, opt_output)
    else
      dbg(nil, "remove:",tmpfile)
      os.remove(tmpfile)
    end
  end

  report_orphan_doubletes()
end



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
--: Embedding documentation in program source files often yields the problem that the
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
--: by a operator sequence. Which in the simplest case is just a single punctuation character,
--: but may have a 'section' name left and a argument right of it. This operators defines how
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
--: <opspec> ::= [section] <operator> [argument]
--:
--: <section> ::= <alphanumeric text including underscore and dots>
--:
--: <operator> ::= ":" | "=" | "@" | "$" | "#" | <user defined operators>
--:
--: <argument> ::= <alphanumeric text including underscore and dots>
--:
--: <documentationtext> ::= <rest of the line>
--: ....
--:
--: There config shipped with pipadoc gives an example to drop a line when it end with "NODOC".
--:
--: IMPORTANT: Pipadoc does not know anything except the line comment characters about the source
--:            programming languages syntax. This includes literal strings and any other
--:            syntactic form which may look like a line comment, but is not. Such lines need to
--:            be dropped by a preprocessor to make them unambiguous.
--:
--: ----
--: const char* example = "//MAIN: this is a C string and not documentation"; //NODOC{NIL}
--: ----
--:
--: Documentation can be either blocked or oneline. Blocks start with a documentation comment
--: including a section or argument specifier but have no documentation text. The text block then
--: follows in documentation commant where section and argument are empty. They span unti a new
--: documentation block is set. Oneline documentation is defined by a documentation comment which
--: sets either section or argument and has a non empty documentation text. They can be
--: interleaved within blocks, after a oneline documentation the preceeding block continues.
--: This is used to define index and glosary items right within block documentation.
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
--:   The line is broken down into it's components and the operators processing
--:   function will be called which is responsible for storing. The ':' operator also does a first
--:   string substitution pass to expand variables.
--:
--: Output Ordering ::
--:   The output order is generated by assembling the toplevel section ('MAIN' if not otherwise
--:   defined). The paste and sorting operators on the toplevel and included sections define the
--:   order of the document.
--:
--: Postprocessing ::
--:   For each output context the postprocessors run and a final string substitution is applied
--:   to the text.
--:
--: Writeout ::
--:   The finished document is written to the output.
--:
--: Report Orphans and Doubletes ::
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
--TODO: DOC Operators are used to define what is a pipadoc comment and how to order the resulting document
--:
--: Built in operators
--: ~~~~~~~~~~~~~~~~~~
--:
--=op_builtin
--:
--:
--: [[CONTEXT]]
--: The Context
--: -----------
--:
--: Processors, operators and string substitution calls and diagnostics get a context passed
--: along. This context represents the state for the actual processed line. It is defined as
--: stack of tables inheriting from each other.
--:
--: On the lowest layer is are the 'DOCVARS' and 'DOCVARS_POST' tables. For each file an
--: immediate 'filecontext' is created and then on top and each line has it's own context.
--: This later per-line context is what gets passed around. The 'DOCVARS_POST' table is only
--: available after postprocessors ran for a final 'strsubst()' pass.
--:
--: In a few cases a fake-context is passed around for diagnostic functions.
--:
--: Context Members
--: ~~~~~~~~~~~~~~~
--:
--: The following members are used/defined in 'contexts'. Some come from the immediate
--: filecontext, which is normally not exposed.
--:
--@context
--:
--:
--: [[DOCVARS]]
--: Documentation Variables
--: -----------------------
--:
--: The 'DOCVARS' and 'DOCVARS_POST' Lua tables holds key/value pairs of variables
--: with the global definitions. These are used by the core and processors/'strsubst().'
--: Simple substitutions can be set from the command line. Configuration files may define
--: more complex lua functions for string substitutions. By default there are no values defined
--: in 'DOCVARS_POST'
--:
--: Predefined DOCVARS
--: ~~~~~~~~~~~~~~~~~~
--:
--@DOCVARS
--:
--:
--TODO: DOCME document 2 ways to modify text strsubst/processors
--: Configuration File
--: ------------------
--:
--: Pipadoc tries to load a configuration file on startup. By default it's named
--: +pipadoc_config.lua+ in the current directory. This name can be changed by the '--config'
--: option.
--:
--: The configuration file is used to define additional pre- and post-processors, define states
--: for those and define custom operators. It is loaded and executed as it own chunk and may only
--: access the global variables (DOCVARS, CONTEXT) and api functions described later.
--:
--:
--: Example Configuration File
--: ~~~~~~~~~~~~~~~~~~~~~~~~~~
--:
--: Pipadoc itself comes with a configuration file for generating it's own documentation and
--: assist the testsuite. This is a good starting point for writing your own configuration.
--:
--: There are pre- and post- processors defined for:
--:
--=shipped_config
--TODO: document that safe operation needs a custom config file
--:
--:
--: Programming API for Extensions
--: ------------------------------
--:
--: Functions pipadoc exports to be used by extensions/config files.
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
--: Pipadoc emits warnings on problems. These are mostly harmless but may need some attention.
--: Warnings are supressed with the '--quiet' option.
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
--: There is a '--make-doc' option which calls the above commands. For convinience
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


--PLANNED: processors get a name, define processing chains
--PLANNED: document pre/post processors in own chapters
--PLANNED: control language/conditionals?  //section?key \{condition\}  else becomes DROPPED:section_key
--PLANNED: not only pipadoc.conf but also pipadoc.sty templates, conf are local only configurations, .sty are global styles
--PLANNED: how to join (and then wordwrap) lines?
--PLANNED: insert empty lines on dedent
--PLANNED: bash like parameter expansion, how to apply that to sections/keys too --%{section}:%{key} .. how about strsubst on SECTION and ARG //{SECTION}:{ARG} NODOC
--PLANNED: org-mode processor
--PLANNED: INIT section for configuration
--PLANNED: test expected stderr in testsuite
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
