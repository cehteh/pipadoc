--PLANNED: make preprocessors markup agnostic? (needs postprocessors)

-- replace {STRING} in pipadoc comments with the first literal string from the code
preprocessor_register ("^lua$",
                       function (str)
                         return str:gsub('^([^"]*"([^"]*)".*--%w*:%w*)(.*){STRING}(.*)', '%1%3%2%4', 1)
                       end
)

--PLANNED: generate function index
-- generate asciidoc formatted documentation for functions
preprocessor_register ("^lua$",
                       function (str)
                         return str:gsub("^(.*function%s+([^)]*%)).*%-%-%w*:%w*)", '%1 +*%2*+::{NL} ', 1)
                       end
)


-- keel track of original file:line as asciidoc comments
local file
local line=0
local origin=true

postprocessor_register ("^asciidoc$",
                        function (text)
                          if text:match("^NOORIGIN") then
                            origin=false
                          else
                            return text
                          end
                        end
)

postprocessor_register ("^asciidoc$",
                        function (text)
                          if text:match("^ORIGIN") then
                            origin=true
                          else
                            return text
                          end
                        end
)


postprocessor_register ("^asciidoc$",
                        function (text)
                          if origin and ( CONTEXT.FILE ~= file or math.abs(CONTEXT.LINE - line) > 4) then
                            text = "// {FILE}:{LINE} //{NL}"..text
                          end

                          file = CONTEXT.FILE
                          line = CONTEXT.LINE
                          return text
                        end
)

-- do string evaluation on all output lines
postprocessor_register ("",
                        function (text)
                          return streval(text)
                        end
)


-- for the testsuite
preprocessor_register ("^test",
                       function (str)
                         local ret,num = str:gsub("TESTPP", '#: TESTFOO')
                         if num > 0 then
                           warn("Test-Substitute TESTPP with #: TESTFOO")
                         end
                         return ret
                       end
)

preprocessor_register ("^test",
                       function (str)
                         local ret,num = str:gsub("TESTFOO", 'TESTBAR')
                         if num > 0 then
                           warn("Test-Substitute TESTFOO with TESTBAR")
                         end
                         return ret
                       end
)


--PLANNED: ldoc/doxygen/javadoc compatible macros @param @return @see etc.


function git_blame (file, line)
  dbg("blame",file, line)
  local result = {}
  local git = io.popen("git blame '"..file.."' -L "..tostring(line)..",+1 -p 2>/dev/null")

  for line in git:lines() do
    local k,v = line:match("^([%a-]+) (.*)")
    if line:match("^([%w]+) (%d+) ") then
      k = 'revision'
      v = line:match("^(%w*)")
    elseif line:match("^\t") then
      k = 'line'
      v = line:match("^\t(.*)")
    end
    result[k] = v
  end
  local _,_,exitcode = git:close()
  return exitcode == 0 and result or nil
end

function git_blame_context ()
  local blame = git_blame (CONTEXT.FILE, CONTEXT.LINE)
  if blame then
    return " +"..DOCVARS.NL..
      "  _"..blame.summary.."_ +"..DOCVARS.NL..
      "  "..blame.author.." "..os.date("%c", tonumber(blame["author-time"])).." +"..DOCVARS.NL..
      "  +"..tostring(blame.revision).."+"
  else
    return ""
  end
end

preprocessor_register ("",
                       function (str)
                         return str:gsub("--FIXME:([^ ]*) (.*)", --NODOC
                                         '--FIXME:%1 {FILE}:{LINE}::{NL}  %2{git_blame_context ()}{NL}') --NODOC
                       end
)


preprocessor_register ("",
                       function (str)
                         return str:gsub("--TODO:([^ ]*) (.*)", --NODOC
                                         '--TODO:%1 {FILE}:{LINE}::{NL}  %2{git_blame_context ()}{NL}') --NODOC
                       end
)

preprocessor_register ("",
                       function (str)
                         return str:gsub("--PLANNED:([^ ]*) (.*)", --NODOC
                                         '--PLANNED:%1 {FILE}:{LINE}::{NL}  %2{git_blame_context ()}{NL}') --NODOC
                       end
)

--PLANNED: offer different sort orders for issues (date / line)
--PLANNED: noweb like preprocessing syntax for chapter substitutions in textfiles

--- Local Variables:
--- mode: lua
--- compile-command: "lua pipadoc.lua -t ISSUES -q pipadoc.lua pipadoc_config.lua pipadoc.install pipadoc.test"
--- End:
