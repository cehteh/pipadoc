
-- replace {STRING} in pipadoc comments with the first literal string from the code
preprocessor_register ("^lua$",
                       function (str)
                         return str:gsub('^([^"]*"([^"]*)".*--%w*:%w*)(.*){STRING}(.*)', '%1%3%2%4', 1)
                       end
)

-- generate asciidoc formatted documentation for functions
preprocessor_register ("^lua$",
                       function (str)
                         return str:gsub("^(.*function%s+([^)]*%)).*--%w*:%w*)", '%1 +*%2*+::{NL} ', 1)
                       end
)

-- for the testsuite
preprocessor_register ("^test",
                       function (str)
                         local ret,num = str:gsub("TESTFOO", 'TESTBAR')
                         if num > 0 then
                           warn("Test-Substitute TESTFOO with TESTBAR")
                         end
                         return ret
                       end
)


--TODO: ldoc/doxygen/javadoc compatible macros @param @return @see etc.


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
                         return str:gsub("--FIXME:([^ ]*) (.*)", '--FIXME:%1 {FILE}:{LINE}::{NL}  %2{git_blame_context ()}{NL}')
                       end
)

preprocessor_register ("",
                       function (str)
                         return str:gsub("--TODO:([^ ]*) (.*)", '--TODO:%1 {FILE}:{LINE}::{NL}  %2{git_blame_context ()}{NL}')
                       end
)

preprocessor_register ("",
                       function (str)
                         return str:gsub("--PLANNED:([^ ]*) (.*)", '--PLANNED:%1 {FILE}:{LINE}::{NL}  %2{git_blame_context ()}{NL}')
                       end
)

--PLANNED: offer different sort orders for issues (date / line)
--PLANNED: noweb like preprocessing syntax for chapter substitutions in textfiles
