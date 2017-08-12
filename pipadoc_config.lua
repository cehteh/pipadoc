--PLANNED: make preprocessors markup agnostic? (needs postprocessors)

--default_config:
--: * Remove any line which ends in 'NODOC'.
preprocessor_register ("",
                       function (context)
                         if context.SOURCE:match("NODOC$") then
                           context.SOURCE = nil
                         end
                       end
)


--: *  Replace '<STRING>' in pipadoc comments with the first literal string from the code.
preprocessor_register ("",
                       function (context)
                         context.SOURCE =
                           context.SOURCE:gsub('^([^"]*"([^"]*)".*%p+%w*:%w*)(.*)<STRING>(.*)',
                                               '%1%3%2%4', 1)
                       end
)


--: * Generate asciidoc formatted documentation for Lua functions.
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
                           context.SOURCE =
                             context.SOURCE:gsub("^(.*function%s+([^)]*%)).*%-%-%w*:%w*)",
                                                 '%1 {FNDEF}', 1)
                         end
                       end
)

--: * Generate an alphabetic index of all public functions and variables.

DOCVARS.FNDEF = "{FNDEF_{MARKUP}}"

DOCVARS.FNDEF_asciidoc = function (context, arg)
  return "anchor:index_"..context.FUNCTION.."[] +*"..context.FUNCTION_PROTO.."*+::{NL}"
end

DOCVARS.FNDEF_text = function (context)
  return context.FUNCTION_PROTO..":{NL}"
end

--: * Generate documentaton for DOCVARS and CONTEXT variables (pipadoc's own documentation).
DOCVARS.DVARDEF = "{DVARDEF_{MARKUP}}"

DOCVARS.DVARDEF_asciidoc = function (context, arg)
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

DOCVARS.DVARDEF_text = function (context, arg)
  for ix in arg:gmatch("([^%s%p]*)[%p%s]*") do
    if #ix > 0 then
      section_append("INDEX", ix:lower(),
                     make_context (context,{TEXT="{INDEXREF "..ix.."}"})
      )
    end
  end

  return arg..":"
end

local lastfirstchar= nil

DOCVARS.INDEXREF = "{INDEXREF_{MARKUP}}"

DOCVARS.INDEXREF_asciidoc = function (context, arg)
  local firstchar = arg:sub(1,1):lower()

  if lastfirstchar ~= firstchar then
    lastfirstchar = firstchar
    return "{NL}[big]#"..firstchar:upper().."# :: {NL}  <<index_"..arg..","..arg..">> +"
  else
    return "  <<index_"..arg..","..arg..">> +"
  end
end

DOCVARS.INDEXREF_text = function (context, arg)
  local firstchar=arg:sub(1,1):lower()

  if lastfirstchar ~= firstchar then
    lastfirstchar = firstchar
    return firstchar:upper()..":{NL}  "..arg
  else
    return "  "..arg
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
                            context.TEXT = nil
                          end
                        end
)

postprocessor_register ("",
                        function (context)
                          if context.TEXT:match("^ORIGIN") then
                            origin=true
                            context.TEXT = nil
                          end
                        end
)

postprocessor_register ("^asciidoc$",
                        function (context)
                          if origin and ( context.FILE ~= file or math.abs(context.LINE - line) > 4) then
                            context.TEXT = "// {FILE}:{LINE} //{NL}"..context.TEXT
                          end

                          file = context.FILE
                          line = context.LINE
                       end
)



-- for the testsuite
if DOCVARS.TESTSUITE then
  DOCVARS.STRING = "example string"
  DOCVARS.STR = "{STRING}"
  DOCVARS.ING = "ING"
  DOCVARS.UPR = "{UPPER}"
  DOCVARS.PING = "{PONG}"
  DOCVARS.PONG = "{PING}"
  DOCVARS.UPPER = function(context, arg)
    return arg:upper()
  end

  preprocessor_register ("^test",
                         function (context)
                           local sub,num = context.SOURCE:gsub("TESTPP", '#: TESTFOO')
                           if num > 0 then
                             context.SOURCE = sub
                             warn(context, "Test-Substitute TESTPP with #: TESTFOO")
                           end
                         end
  )


  preprocessor_register ("^test",
                         function (context)
                           local sub,num = context.SOURCE:gsub("TESTFOO", 'TESTBAR')
                           if num > 0 then
                             context.SOURCE = sub
                             warn(context, "Test-Substitute TESTFOO with TESTBAR")
                           end
                         end
  )
end

--PLANNED: ldoc/doxygen/javadoc compatible macros @param @return @see etc.

--: * Generate formatted lists for doc comments in WIP/FIXME/TODO/PLANNED/DONE sections.
--:   Each such item includes information gathered from the git commit which touched
--:   that line last.
if DOCVARS.GIT then
  DOCVARS.GIT_BLAME = function (context)
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

  DOCVARS.GIT_BLAME_asciidoc = " +{NL}  _{GIT_BLAME_SUMMARY}_ +{NL}  {GIT_BLAME_AUTHOR}, {GIT_BLAME_DATE} +{NL}  +{GIT_BLAME_REVISION}+"
  DOCVARS.GIT_BLAME_text = " {NL}  {GIT_BLAME_SUMMARY}{NL}  {GIT_BLAME_AUTHOR},  {GIT_BLAME_DATE} {NL}  {GIT_BLAME_REVISION}"

else
  DOCVARS.GIT_BLAME = ""
end


local issues_keywords = {"WIP", "FIXME", "TODO", "PLANNED", "DONE"}

-- nobug annotations
preprocessor_register ("^c$",
                       function (str)
                         local ret, rep
                         for _,word in ipairs(issues_keywords) do
                           ret, rep = str:gsub('(%s*'..word..'%s*%("([^"]*).*)',
                                                '%1 //'..word..': %2', 1)
                           if rep > 0 then
                             return ret
                           end
                         end
                         return str
                       end
)

preprocessor_register ("",
                       function (str)
                         local ret, rep
                         for _,word in ipairs(issues_keywords) do
                           ret, rep = str:gsub("("..word.."):([^%s]*)%s?(.*)",
                                               '%1:0%2 {FILE}:{LINE}::{NL}  %3{git_blame_context ()}{NL}', 1)

preprocessor_register ("",
                       function (context)
                         for _,word in ipairs(issues_keywords) do
                           context.SOURCE = context.SOURCE:gsub(
                             "("..word.."):([^%s]*)%s?(.*)",
                             '%1:0%2 {FILE}:{LINE}::{NL}  %3{GIT_BLAME}{NL}', 1)
                         end
                       end
)




--TODO: docmument, postprocessor cant section_append
--PLANNED: offer different sort orders for issues (date / line)
--PLANNED: noweb like preprocessing syntax for chapter substitutions in textfiles

--- Local Variables:
--- mode: lua
--- compile-command: "lua pipadoc.lua --issues --make-doc"
--- End:
