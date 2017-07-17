--PLANNED: make preprocessors markup agnostic? (needs postprocessors)

--default_config:
--: * Remove any line which ends in 'NODOC'.
preprocessor_register ("",
                       function (str)
                         if not str:match("NODOC$") then
                           return str
                         end
                       end
)


--: *  Replace '<STRING>' in pipadoc comments with the first literal string from the code.
preprocessor_register ("",
                       function (str)
                         return str:gsub('^([^"]*"([^"]*)".*%p+%w*:%w*)(.*)<STRING>(.*)', '%1%3%2%4', 1)
                       end
)

--: * Generate asciidoc formatted documentation for Lua functions.
preprocessor_register ("^lua$",
                       function (str)
                         local fn = str:match("function%s+([^(%s]*).*%-%-%w*:%w*")
                         if fn then
                           section_append("INDEX", fn:lower(), {
                                            FILE=CONTEXT.FILE,
                                            LINE=CONTEXT.LINE,
                                            TEXT="{indexref('"..fn.."')}"
                           })
                           return str:gsub("^(.*function%s+([^)]*%)).*%-%-%w*:%w*)",
                                           '%1 {fndef("'..fn..'","%2")}', 1)
                         end
                         return str
                       end
)

--: * Generate an alphabetic index of all public functions and variables.
function fndef(id, text)
  text = text or id
  return "anchor:index_"..id.."[]+*"..text.."*+::"..DOCVARS.NL.." "
end

function indexdef(id, text)
  section_append("INDEX", id:lower(), {
                   FILE=CONTEXT.FILE,
                   LINE=CONTEXT.LINE,
                   TEXT="{indexref('"..id.."')}"
  })

  text = text or id
  return "anchor:index_"..id.."[]`"..text.."`::"..DOCVARS.NL
end

function vardef(id, text)
  local anchors = ""
  for ix in id:gmatch("([^%s,]*)[,%s]*") do
    if #ix > 0 then
      section_append("INDEX", ix:lower(), {
                       FILE=CONTEXT.FILE,
                       LINE=CONTEXT.LINE,
                       TEXT="{indexref('"..ix.."')}"
      })

      anchors=anchors.."anchor:index_"..ix.."[]"
    end
  end

  text = text or id
  return anchors.."`"..text.."`::"..DOCVARS.NL
end

local lastfirstchar= nil

function indexref(id, text)
  local firstchar=id:sub(1,1):lower()

  text = text or id

  if lastfirstchar ~= firstchar then
    lastfirstchar = firstchar
    return "{nbsp} :: "..DOCVARS.NL.."[big]#"..firstchar:upper().."# :: "..DOCVARS.NL..
      "<<index_"..id..","..id..">>{nbsp}{nbsp}{nbsp}{nbsp}{nbsp}"
  else
    return "<<index_"..id..","..id..">>{nbsp}{nbsp}{nbsp}{nbsp}{nbsp}"
  end
end


--: * Keep track of original file:line as asciidoc comments in the output.
--:   Disable this tracking when a doc comment starts with 'NOORIGIN' and
--:   re-enable it with a doc comment starting with 'ORGIN'.
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

--: * Do string evaluation on all output lines.
postprocessor_register ("",
                        function (text)
                          return streval(text)
                        end
)


-- for the testsuite
if DOCVARS.TESTSUITE then
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

  postprocessor_register ("",
                          function (text)
                            if text:match("TESTDROP") then
                              warn("TESTDROP")
                              return
                            end
                            return text
                          end
  )
end

--PLANNED: ldoc/doxygen/javadoc compatible macros @param @return @see etc.

--: * Generate asciidoc formatted lists for doc comments in FIXME/TODO/PLANNED sections.
--:   Each such item includes information gathered from the git commit which touched
--:   that line last.

if DOCVARS.GIT then
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
else
  function git_blame_context ()
    return ""
  end
end


local issues_keywords = {"FIXME", "TODO", "PLANNED"}

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

                           if rep > 0 then
                             return ret
                           end
                         end
                         return str
                       end
)

--TODO: file given twice as input warn and drop (registry of already read files)
--PLANNED: offer different sort orders for issues (date / line)
--PLANNED: noweb like preprocessing syntax for chapter substitutions in textfiles

--- Local Variables:
--- mode: lua
--- compile-command: "lua pipadoc.lua --make-doc -D GIT -t ISSUES pipadoc.lua pipadoc_config.lua pipadoc.install"
--- End:
