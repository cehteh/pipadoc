local args_done = false
local opt_verbose = 1
local opt_nodefaults = false
local opt_top = "MAIN"
local do_nothing = false
local opt_inputs = {}

function printerr(...)
  for i,v in ipairs {...} do
    if i > 1 then io.stderr:write("\t") end
    io.stderr:write(tostring(v))
  end
  io.stderr:write("\n")
end

function msg(lvl,...)
  if lvl <= opt_verbose then
    printerr(...)
  end
end
function warn(...) msg(1, ...) end
function echo(...) msg(2, ...) end
function dbg(...) msg(3, ...) end

function die(...)
  printerr(...)
  os.exit(1)
end


-- try to load optional modules
function request(name)
   local ok,handle = pcall(require, name)
   if ok then
      return handle
   else
      warn("Can't load module:", name)
      return nil
   end
end

request "luarocks.loader"
lfs = request "lfs"


function assert_type(var, expected)
  assert(type(var) == expected, "type error: "..expected.." expected")
  return var
end

function assert_notnil(var)
  assert(type(var) ~= "nil", "Value expected")
  return var
end

function to_table(v)
   if type(v) ~= 'table' then
      v = {v}
   end
   return v
end

function help()
   print [[
         --: TODO
         TODO
   ]]
   os.exit(0)
end

-- Options





--:linecomments
--: Linecomments
--: ------------
--:
--: Pipadoc needs to know about the syntax of line comments of the files it is reading. For this one can
--: register patterns to be matched against the filename together with a list of line comment characters.
--:
--: Pipadoc includes definitions for some common linecomments already.
--:
--: Noteworthy is that when a line comment is defined as an empty string ("") then every line of a file is
--: considered as documentation but no special operations apply. This is used for parsing plaintext documentation
--: files. Which also uses the "PIPADOC" keyword to enable special operations within text files.
--:
-- :    function (line, docseqs)


local linecomments = {}

function register_linecomments(names, linecommentseqs)
  names = to_table(names)
  linecommentseqs = to_table(linecommentseqs)
  for i=1,#names do
    linecomments[names[i]] = linecomments[names[i]] or {}
    for j=1,#linecommentseqs do
      dbg("register linecomment:", names[i], linecommentseqs[j])
      linecomments[names[i]][#linecomments[names[i]]+1] = linecommentseqs[j]
    end
  end
end

function get_linecomments(filename)
  assert_type(filename, "string")
  for k,v in pairs(linecomments) do
    if string.match(filename, k) then
      return v
    end
  end
end

function select_linecomment(line, linecommentseqs)
  for i=1,#linecommentseqs do
    if string.match(line, linecommentseqs[i]) then
      return linecommentseqs[i]
    end
  end
end


local sections = {}
local sections_usecnt = {}

--:proc
--: Processors
--: ----------
--:
--: Processors are functions are the core functionality of pipadoc. Lines read from
--: files are handed to each registered processor in order, the processor is free to modify
--: this line (by returning a mutated copy) and/or calling any API function to do some action.
--: When a processor returns 'nil'. The processing chain ends and no further processors are called.
--:
--:  
--: 
--: 
--: Pipadoc inserts the 'default' at the end of the chain.
--: 
-- :    function (line, docseqs)


local processors_available = {}
function register_processor(name, func)
  processors_available[assert_type(name, "string")] = assert_type(func, "function")
end


local processors_enabled = {}
function enable_processor(name, pattern)
  table.insert(processors_enabled, {assert_type(pattern, "string"), assert_type(name, "string")})
end


--TODO function request_processor(name)
--   table.insert(processors_enabled, {assert_type(pattern, "string"), assert_type(name, "string")})
--end


--:op
--: Operations
--: ----------
--: 
--: 


-- dynop, last comment char extends to docchar

local operations = {}


function register_operation(pattern, func)
  operations[pattern] = func
end







--end


--: demo













local options = {
  ["--"] = function () args_done=true end,
  ["-v"] = "--verbose",
  ["--verbose"] = function () opt_verbose = opt_verbose+1 end,
  ["-q"] = "--quiet",
  ["--quiet"] = function () opt_verbose = 0 end,
  ["-d"] = "--debug",
  ["--debug"] = function () opt_verbose = 3 end,
  ["-h"] = "--help",
  ["--help"] = help,
  ["-c"] = "--comment",
  ["--comment"] = function (arg,i)
                    assert(type(arg[i+2]))
                    register_linecomment(arg[i+1], arg[i+2])
                    return 2
                  end,
  -- --alias match pattern --file-as match filename
  ["-t"] = "--top",
  ["--top"] = function (arg, i)
                assert(type(arg[i+1]))
                opt_top = arg[i+1]
                return 1
              end,
  -- -o --output
  -- -l --loadn
  ["-n"] = "--do-nothing",
  ["--do-nothing"] = function () do_nothing = true end,
  ["--no-defaults"] = function () opt_nodefaults = true end,
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

function parse_commandline()
  parse_args(arg)
end












function setup()
  parse_commandline()
  
  if not opt_nodefaults then
    register_linecomments({"%.c$","%.cpp$","%.C$", "%.cxx$", "%.h$"}, {"//", "/*"})
    register_linecomments({"%.lua$", pluginext}, "%-%-")
    register_linecomments({"^Makefile$", "%.mk$", "%.make$"}, "#")
    register_linecomments({"%.sh$", "%.pl$", "%.awk$", }, "#")
    register_linecomments({"%.pro$", "%.P$"}, "%")
    register_linecomments({"%.txt$", "%.TXT$", "%.pdoc$", "^-$"}, {"PIPADOC", ""})
  end

  --   for plugin in pairs(plugins) do
  --      load_plugin(plugin)
  --   end

  register_processor(
    "verbatim",
    function (line, linecommentseqs, file)
      local comment = select_linecomment(line, linecommentseqs)
      if comment then
        local code, before, pattern, after = string.match(line, "(.*)"..comment.."(.*)VERBATIM^(.*)$(.*)")
        if code then
          code = string.match(code, pattern)
          if code then
            return comment..before..tostring(code)..after
          else
            warn("VERBATIM pattern did not match")
          end
        else
          code, before, after = string.match(line, "(.*)"..comment.."^(.*)VERBATIM(.*)$")
          if code then
            return before..tostring(pre)..after
          end
        end
      end
      return line
    end)



  --[[  dd
  register_operation(
    "!",
    function (arg, text)
      -- DIRECTIVE load unused reuse
    end)
  --]]

  --[[
  register_operation(
    "@",
    function (arg, text)
      return nil
    end)
  --]]
  register_operation(
    "=",
    function (arg, text)
      local section = sections[current_section] or {}
      section[#section+1] = { "section", arg }
      return nil
    end)

  register_operation(
    ":",
    function (arg, text)
      if #arg > 0 then
        current_section = arg
        --FIXME subsection
        dbg("section:", arg)
      end
      return text
    end)


  -- op- processor
  
  -- register_processor(
  --    function (line, linecommentseqs, file)
  --       local comment = select_linecomment(line, linecommentseqs)
  --       if comment then

  --       local pre, pat, op, arg, spc, text
  
  --       for i=1,#docseqs do
  
  --          if #docseqs[i] > 0 then
  --             pre, doc, op, arg, spc, text = string.match(line, "^(.*)("..docseqs[i]..")(%p*)(%S*)(%s?)(.*)$")
  --          else
  --             pre = ""
  --             doc = ""
  --             op =  ""
  --             arg = ""
  --             spc = ""
  --             text = line
  --          end

  -- --         dbg("pre:",pre, "pat:", pat, "op:", op, "arg:", arg, "text:", text)

  --          if pre then
  --             if operations[op] then
  --                dbg("op:", op)
  --                while operations[op] do
  --                   op = operations[op]
  --                end
  --                text = op(arg, text)
  --             else
  --                warn("unknown operator:", op)
  --             end
  
  --             if text then
  --                dbg("out:", text)
  --                local section = sections[current_section] or {}
  --                section[#section+1] = { "text", text }
  --             end
  --             break
  --          end
  --       end
  --    end)
end

function process_file(file)
  local linecommentseqs = get_linecomments(file)
  if not linecommentseqs then
    warn("unknown file type:", file)
    return
  end

  local initial_section = string.match(file, "%.*([^.]*)")
  local current_section = initial_section
  dbg("section:", current_section)


  local fh
  if file == '-' then
    fh = io.stdin
  else
    fh = io.open(file)
    if not fh then
      warn("file not found:", file)
      return
    end
  end

  for line in fh:lines() do
    dbg("line:", line)
    for i=1,#processors do
      line = processors[i](line, linecommentseqs, file)
    end
  end
  fh:close()
end

function process_inputs()
  if not do_nothing then
    for i=1,#opt_inputs do
      --:TODO globbing if no such file exists

      --            process_file(inputs[i])
    end
  end
end




setup()
process_inputs()
-- generate output
-- orphans / doublettes

--function make_set(keys)
--  assert(type(keys) == 'table')
-- local set={}
-- for i=1,#keys do
--   assert(set[keys[i]] == nil)
--  set[keys[i]] = true
--   end
--  return set
--end
