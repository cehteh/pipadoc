--PLANNED: make preprocessors markup agnostic? (needs postprocessors)

--shipped_config:
--: * Remove any line which ends in 'NODOC'.
preprocessor_register ("",
                       function (context)
                         if context.SOURCE:match("NODOC$") then
                           return false
                         else
                           return true
                         end
                       end
)


--: *  Replace '<STRING>' in pipadoc comments with the first literal string from the code.
--:    Lifts string literals from sourcecode to documentation.
preprocessor_register ("",
                       {
                         '^([^"]*"([^"]*)".*%p+%w*:%w*)(.*)<STRING>(.*)',
                         '%1%3%2%4',
                         1
                       }
)


--: * Automatic generation of documentation for Lua functions.
--:   Generates an index entry and a prototype documentation from a function definition
preprocessor_register ("^lua$",
                       function (context)
                         local proto,fn = context.SOURCE:match(
                           "^[^\"']*function%s+(([^(%s]*)[^)]*%)).*%-%-%w*:%w*")

                         if fn then
                           section_append("INDEX", fn:lower(),
                                          make_context( context, {TEXT="{INDEXREF "..fn.."}"})
                           )
                           context.FUNCTION = fn
                           context.FUNCTION_PROTO = proto
                           return context.SOURCE:gsub("^(.*function%s+([^)]*%)).*%-%-%w*:%w*)",
                                                       '%1 {FNDEF}', 1)
                         else
                           return true
                         end
                       end
)


GLOBAL.FNDEF = "{FNDEF_{MARKUP}}"

GLOBAL.FNDEF_asciidoc = function (context, arg)
  return "anchor:index_"..context.FUNCTION.."[] +*"..context.FUNCTION_PROTO.."*+::{NL}"
end

GLOBAL.FNDEF_text = function (context)
  return context.FUNCTION_PROTO..":{NL}"
end

--: * Generate documentaton for GLOBAL and CONTEXT variables (pipadoc's own documentation).
GLOBAL.VARDEF = "{VARDEF_{MARKUP}}"

GLOBAL.VARDEF_asciidoc = function (context, arg)
  local anchors = ""
  for ix in arg:gmatch("([^%s%p]*)[%p%s]*") do
    if #ix > 0 then
      section_append("INDEX", ix:lower(),
                     make_context (context,{TEXT="{INDEXREF "..ix.."}"})
      )

      anchors=anchors.."anchor:index_"..ix.."[]"
    end
  end

  return anchors.."`"..arg.."`::"
end

GLOBAL.VARDEF_text = function (context, arg)
  for ix in arg:gmatch("([^%s%p]*)[%p%s]*") do
    if #ix > 0 then
      section_append("INDEX", ix:lower(),
                     make_context (context,{TEXT="{INDEXREF "..ix.."}"})
      )
    end
  end

  return arg..":"
end

--: * Generate a sorted index of functions and doc variables.
local lastfirstchar= nil

GLOBAL.INDEXREF = "{INDEXREF_{MARKUP}}"

GLOBAL.INDEXREF_asciidoc = function (context, arg)
  local firstchar = arg:sub(1,1):lower()

  if lastfirstchar ~= firstchar then
    lastfirstchar = firstchar
    return "{NL}[big]#"..firstchar:upper().."# :: {NL}  <<index_"..arg..","..arg..">> +"
  else
    return "  <<index_"..arg:gsub("%W","_")..","..arg..">> +"
  end
end

GLOBAL.INDEXREF_text = function (context, arg)
  local firstchar=arg:sub(1,1):lower()

  if lastfirstchar ~= firstchar then
    lastfirstchar = firstchar
    return firstchar:upper()..":{NL}  "..arg
  else
    return "  "..arg
  end
end



--: *  Asciidoc helpers for paragraphs, and headers.
--:    Replace '\{PARA <title>;[index];[description]\}' and
--:    '\{HEAD [level] <title>;[index];[description]\}' with asciidoc entities.
--:    When 'index' is given an entry in the index will be generated.
--:
--:    For headers 'level' can be one of:
--:
--:    empty ::
--:      Header on the same level as the current remembered level
--:    -,~,^,+ ::
--:      The corresponding asciidoc header.
--:      Remembers the level.
--:    >.. ::
--:      Temporary deeper level by the number of '>' signs.
--:    <.. ::
--:      Temporary higher level by the number of '<' signs.
--:    ++ ::
--:      Increase the remembered header level by one.
--:    -- ::
--:      Decrease the remembered header level by one.
--:
--:    The reason for these elaborate definitions is that when pasting documentation together
--:    it is not always clear what the header level of the surrounding environment is.
--:
--TODO: if GLOBAL.ASCIIDOCHELP
if GLOBAL.MARKUP == "asciidoc" then
  GLOBAL.PARA = function (context, arg)
    local title, index, descr = arg:match("([^;]*); *([^;]*); *(.*)")
    --TODO: descr is dropped
    if title and title ~= "" then

      if index ~= "" then
        local id = index:gsub("%W","_")
        title = "[[index_"..id.."]]{NL}."..title
        section_append("INDEX", id:lower(),
                       make_context (context,
                                     {TEXT="{INDEXREF "..index.."}"}
                       )
        )
      else
        title = "."..title
      end

      return title
    end
  end

  local asciidoc_levels = { "=","-", "~", "^", "+",
                            ["="]=1, ["-"]=2, ["~"]=3, ["^"]=4, ["+"]=5
  }
  local asciidoc_lastlevel = "-"


  GLOBAL.HEAD = function (context, arg)
    local title, index, descr = arg:match("^%p* *([^;]*); *([^;]*); *(.*)")
    --TODO: descr is dropped

    if title and title ~= "" then
      if index ~= "" then
        local id = index:gsub("%W","_")
        title = "[[index_"..id.."]]{NL}"..title
        section_append("INDEX", id:lower(),
                       make_context (context,
                                     {TEXT="{INDEXREF "..index.."}"}
                       )
        )
      end
    end

    return "{HEAD_POST "..arg.."}"
  end


  GLOBAL_POST.HEAD_POST = function (context, arg)
    local level, title = arg:match("^(%p*) *([^;]*).*")

    if level == '' then
      level = asciidoc_lastlevel
    elseif asciidoc_levels[level] then
      asciidoc_lastlevel = level
    elseif level:sub(1,1) == '>' then
      local l = asciidoc_levels[asciidoc_lastlevel]+#level
      l = l > 5 and 5 or l
      level = asciidoc_levels[l]
    elseif level:sub(1,1) == '<' then
      local l = asciidoc_levels[asciidoc_lastlevel]-#level
      l = l < 2 and 2 or l
      level = asciidoc_levels[l]
    elseif level == '++' then
      local l = asciidoc_levels[asciidoc_lastlevel]+1
      l = l > 5 and 5 or l
      level = asciidoc_levels[l]
      asciidoc_lastlevel = level
    elseif level == '--' then
      local l = asciidoc_levels[asciidoc_lastlevel]-1
      l = l < 2 and 2 or l
      level = asciidoc_levels[l]
      asciidoc_lastlevel = level
    else
      warn(context, "unknown header level", level) --cwarn: <STRING> ::
      --cwarn:  Asciidoc helper "HEAD" with unknown level.
    end

    level = title:gsub(".", level)

    return title.."{NL}"..level
  end
end


--: * Keep track of original file:line as asciidoc comments in the output.
--:   Disable this tracking when a doc comment starts with 'NOORIGIN' and
--:   re-enable it with a doc comment starting with 'ORGIN'.
local file
local line=0
local origin=true

postprocessor_register ("",
                        function (context)
                          if context.TEXT:match("^NOORIGIN") then
                            origin=false
                            return false
                          end
                          return true
                        end
)

postprocessor_register ("",
                        function (context)
                          if context.TEXT:match("^ORIGIN") then
                            origin=true
                            return false
                          end
                          return true
                        end
)

postprocessor_register ("^asciidoc$",
                        function (context)
                          result = context.TEXT
                          if origin and ( context.FILE ~= file or math.abs(context.LINE - line) > 4) then
                            result = "// {FILE}:{LINE} //{NL}"..result
                          end

                          file = context.FILE
                          line = context.LINE
                          return result
                       end
)




--: * Generate formatted lists for doc comments in WIP/FIXME/TODO/PLANNED/DONE sections.
--:   When GLOBAL.GIT is defined ('-D GIT') then each such item includes information gathered
--:   from the git commit which touched that line the last.
--:   When GLOBAL.NOBUG is defined it reaps http://nobug.pipapo.org[NoBug] annotations from
--:   C source files as well.
if GLOBAL.GIT then
  GLOBAL.GIT_BLAME = function (context)
    local git = io.popen("git blame '"..context.FILE.."' -L "..tostring(context.LINE)..",+1 -p 2>/dev/null")

    local blame = {}
    for line in git:lines() do
      local k,v = line:match("^([%a-]+) (.*)")
      if line:match("^([%w]+) (%d+) ") then
        k = 'revision'
        v = line:match("^(%w*)")
      elseif line:match("^\t") then
        k = 'line'
        v = line:match("^\t(.*)")
      end
      blame[k] = v
    end
    local ok,_,exitcode = git:close()

    if not ok then
      warn(context, "git blame failed:", exitcode)
      return ""
    end

    local blame_date
    if blame.revision == "0000000000000000000000000000000000000000" then
      blame_date = ""
    else
      blame_date = os.date("%c", blame["author-time"])
    end

    context.GIT_BLAME_SUMMARY = blame.summary
    context.GIT_BLAME_AUTHOR = blame.author
    context.GIT_BLAME_DATE = blame_date
    context.GIT_BLAME_REVISION = blame.revision

    return "{GIT_BLAME_{MARKUP}}"
  end

  GLOBAL.GIT_BLAME_asciidoc = " +{NL}  _{GIT_BLAME_SUMMARY}_ +{NL}  {GIT_BLAME_AUTHOR}, {GIT_BLAME_DATE} +{NL}  +{GIT_BLAME_REVISION}+"
  GLOBAL.GIT_BLAME_text = " {NL}  {GIT_BLAME_SUMMARY}{NL}  {GIT_BLAME_AUTHOR},  {GIT_BLAME_DATE} {NL}  {GIT_BLAME_REVISION}"

else
  GLOBAL.GIT_BLAME = ""
end

local issues_keywords = {"WIP", "FIXME", "TODO", "PLANNED", "DONE"}

if GLOBAL.NOBUG then
  preprocessor_register ("^c$",
                         function (context)
                           for _,word in ipairs(issues_keywords) do
                             context.SOURCE = context.SOURCE:gsub(
                               '(%s*'..word..'%s*%("([^"]*).*)',
                               '%1 //'..word..': %2', 1)
                           end
                           return true
                         end
  )
end

--FIXME: pass comments in filecontext, match all instead %p
preprocessor_register ("",
                       function (context)
                         for _,word in ipairs(issues_keywords) do
                           context.SOURCE = context.SOURCE:gsub(
                             "(%p"..word.."):([^%s]*)%s?(.*)",
                             '%1:0%2 {FILE}:{LINE}::{NL}  %3{GIT_BLAME}{NL}', 1)
                         end
                         return true
                       end
)


-- for the testsuite
if GLOBAL.TESTSUITE then
  GLOBAL.STRING = "example string"
  GLOBAL.STR = "{STRING}"
  GLOBAL.ING = "ING"
  GLOBAL.UPR = "{UPPER}"
  GLOBAL.PING = "{PONG}"
  GLOBAL.PONG = "{PING}"
  GLOBAL.UPPER = function(context, arg)
    return arg:upper()
  end

  preprocessor_register ("^test",
                         function (context)
                           local sub,num = context.SOURCE:gsub("TESTPP", '#: TESTFOO')
                           if num > 0 then
                             context.SOURCE = sub
                             warn(context, "Test-Substitute TESTPP with #: TESTFOO")
                           end
                           return true
                         end
  )


  preprocessor_register ("^test",
                         function (context)
                           local sub,num = context.SOURCE:gsub("TESTFOO", 'TESTBAR')
                           if num > 0 then
                             context.SOURCE = sub
                             warn(context, "Test-Substitute TESTFOO with TESTBAR")
                           end
                           return true
                         end
  )
end

--TODO: docmument, postprocessor cant section_append
--PLANNED: offer different sort orders for issues (date / line)
--PLANNED: noweb like preprocessing syntax for chapter substitutions in textfiles
--PLANNED: check that issues are unique
--PLANNED: ldoc/doxygen/javadoc compatible macros @param @return @see etc.

--- Local Variables:
--- mode: lua
--- compile-command: "lua pipadoc.lua --issues --make-doc"
--- End:
