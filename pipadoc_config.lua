--shipped_config_pre:
--: * Ignore any line which ends in 'NODOC'.
preprocessor_register (nil,
                       function (context)
                         if context.SOURCE:match("NODOC$") then
                           return false
                         else
                           return true
                         end
                       end
)


--shipped_config_pre:
--: *  Replace '<STRING>' with the first literal doublequoted string from the code.
--:    This lifts string literals from sourcecode to documentation. The doublequotes are removed.
preprocessor_register (nil,
                       {
                         '^([^"]*"([^"]*)".*%p+%w*:%w*)(.*)<STRING>(.*)',
                         '%1%3%2%4',
                         1
                       }
)


--shipped_config_pre:
--: *  Replaces '<HEXSTRING>' with the first literal doublequoted string from the code
--:    converted to lowercase hexadecimal (useable for sorting including whitespace and punctuation).
--:    When no literal doublequoted string exists in the code, then the last used hexadecimal
--:    string found is used. Used for sorting documentation by the lifted string literal.
local hexstring

preprocessor_register (nil,
                       function (context)
                         local literal_string = context.SOURCE:match('^[^"]*"([^"]*)".-<HEXSTRING>')

                         if literal_string then
                           hexstring = string_tohex(literal_string:lower())
                         end

                         if context.SOURCE:match('<HEXSTRING>') then
                           return context.SOURCE:gsub('<HEXSTRING>',
                                                      hexstring,
                                                      1
                           )
                         end

                         return true
                         end
)


--shipped_config_pre:
--: * Automatic generation of documentation for Lua functions.
--:   Generates an index entry and a prototype header from an one line function definition
preprocessor_register ("^lua$",
                       function (context)
                         local proto,fn = context.SOURCE:match(
                           "^[^\"']*function%s+(([^(%s]*)[^)]*%)).*%-%-%w*:%w*")

                         if fn then
                           dbg(context, "lua function", fn)
                           section_append("INDEX", fn:lower(),
                                          context_new( context, {TEXT="{INDEX_ENTRY "..fn.."}"})
                           )
                           context.FUNCTION = fn
                           context.FUNCTION_PROTO = proto
                           return context.SOURCE:gsub("^(.*function%s+([^)]*%)).*%-%-%w*:%w*)",
                                                       '%1 {LUA_FNDEF}', 1)
                         else
                           return true
                         end
                       end
)



--shipped_config_subst:
--: {MACRODEF BRACED argument}
--: Puts 'argument' in curly braces. Escapes this curly braces
--: depending on the markup engine selected that they appear in the output.
--:
GLOBAL.BRACED = "{BRACED_{MARKUP} {__ARG__}}"
GLOBAL.BRACED_text = "{__BRACEOPEN__}{__ARG__}{__BRACECLOSE__}"
GLOBAL.BRACED_asciidoc = "{__BACKSLASH__}{__BRACEOPEN__}{__ARG__}{__BRACECLOSE__}"

--shipped_config_subst:
--: {MACRODEF LINEBREAK}
--: Emit a forced linebreak into the markup.
--:
GLOBAL.LINEBREAK = "{LINEBREAK_{MARKUP}}"
GLOBAL.LINEBREAK_text = "`{NL}"
GLOBAL.LINEBREAK_asciidoc = " +{NL}"


--PLANNED: ESCAPE function which escapes all strsubst

--shipped_config_subst:
--: {MACRODEF LUA_FNDEF}
--: Lift a Lua function definition to the documentation text.
--: Used by the Lua documentation preprocessor.
--:
GLOBAL.LUA_FNDEF = "{LUA_FNDEF_{MARKUP}}"

GLOBAL.LUA_FNDEF_text = function (context)
  return strsubst(context, context.FUNCTION_PROTO..":{NL}")
end

GLOBAL.LUA_FNDEF_asciidoc = function (context, arg)
  return strsubst(context, "anchor:index_"..context.FUNCTION.."[] +*"..context.FUNCTION_PROTO.."*+::{NL}")
end

GLOBAL.LUA_FNDEF_orgmode = function (context, arg)
  return strsubst(context, "<<index_"..context.FUNCTION..">> - -"..context.FUNCTION_PROTO.."- ::{NL}")
end




--shipped_config_subst:
--: {MACRODEF VARDEF name}
--: Generate a header and index entry for 'name'. Used for documentaton of GLOBAL and CONTEXT variables
--: (pipadoc's own documentation).
--:
GLOBAL.VARDEF = "{VARDEF_{MARKUP} {__ARG__}}"

GLOBAL.VARDEF_text = function (context, arg)
  arg = strsubst(context, arg)
  for ix in arg:gmatch("([^%s%p]*)[%p%s]*") do
    if #ix > 0 then
      section_append("INDEX", ix:lower(),
                     context_new (context,{TEXT="{INDEX_ENTRY "..ix.."}"})
      )
    end
  end

  return strsubst(context, arg..":")
end

GLOBAL.VARDEF_asciidoc = function (context, arg)
  local anchors = ""
  arg = strsubst(context, arg)
  for ix in arg:gmatch("([^%s%p]*)[%p%s]*") do
    if #ix > 0 then
      section_append("INDEX", ix:lower(),
                     context_new (context,{TEXT="{INDEX_ENTRY "..ix.."}"})
      )

      anchors=anchors.."anchor:index_"..ix.."[]"
    end
  end

  return strsubst(context, anchors.."`"..arg.."`::")
end


GLOBAL.VARDEF_orgmode = function (context, arg)
  local anchors = ""
  arg = strsubst(context, arg)
  for ix in arg:gmatch("([^%s%p]*)[%p%s]*") do
    if #ix > 0 then
      section_append("INDEX", ix:lower(),
                     context_new (context,{TEXT="{INDEX_ENTRY "..ix.."}"})
      )

      anchors=anchors.."<<index_"..ix..">>"
    end
  end

  return strsubst(context, anchors.."- -"..arg.."- ::")
end


--shipped_config_subst:
--: {MACRODEF MACRODEF arguments...}
--: generates a header and index entry for a macro.
--: Used for documentaton of the string substitution language.
--:
GLOBAL.MACRODEF = "{MACRODEF_{MARKUP} {__ARG__}}"

GLOBAL.MACRODEF_text = function (context, arg)
  arg = strsubst(context, arg)
  ix = arg:match("%S*")

  section_append("INDEX", ix:lower(),
                 context_new (context,{TEXT="{INDEX_ENTRY "..ix.."}"})
  )

  return strsubst(context, ""..arg..":")
end

GLOBAL.MACRODEF_asciidoc = function (context, arg)
  arg = strsubst(context, arg)
  ix = arg:match("%S*")

  section_append("INDEX", ix:lower(),
                 context_new (context,{TEXT="{INDEX_ENTRY "..ix.."}"})
  )

  return strsubst(context, "anchor:index_"..ix.."[]+\\\\{"..arg.."\\}+ ::", 'escape')
end


GLOBAL.MACRODEF_orgmode = function (context, arg)
  arg = strsubst(context, arg)
  ix = arg:match("%S*")

  section_append("INDEX", ix:lower(),
                 context_new (context,{TEXT="{INDEX_ENTRY "..ix.."}"})
  )

  --TODO: anchor not implemented yet
  return strsubst(context, "- -"..arg.."- ::")
end


--shipped_config_subst:
--: {MACRODEF MACRODEFSP argument}
--: generates a header and index entry for a macro using the 'special form'.
--: Used for documentaton of the string substitution language.
--:
GLOBAL.MACRODEFSP = "{MACRODEFSP_{MARKUP} {__ARG__}}"

GLOBAL.MACRODEFSP_text = function (context, arg)
  arg = strsubst(context, arg)
  ix = arg:match("%S*")

  section_append("INDEX", ix:lower(),
                 context_new (context,{TEXT="{INDEX_ENTRY "..ix.."}"})
  )

  return strsubst(context, ""..arg.." <special>:")
end

GLOBAL.MACRODEFSP_asciidoc = function (context, arg)
  arg = strsubst(context, arg)
  ix = arg:match("%S*")

  section_append("INDEX", ix:lower(),
                 context_new (context,{TEXT="{INDEX_ENTRY "..ix.."}"})
  )

  return strsubst(context, "anchor:index_"..ix.."[]+\\\\{"..arg.."\\}+ _^special^_ ::", 'escape')
end


GLOBAL.MACRODEFSP_orgmode = function (context, arg)
  arg = strsubst(context, arg)
  ix = arg:match("%S*")

  section_append("INDEX", ix:lower(),
                 context_new (context,{TEXT="{INDEX_ENTRY "..ix.."}"})
  )

  --PLANNED:A anchor not implemented yet
  return strsubst(context, "- -"..arg.."- <special> ::")
end


--shipped_config_subst:
--: {MACRODEF INDEX_ENTRY name}
--: Create an entry in the index that refers back to 'name'.
--:
local lastfirstchar= nil

GLOBAL.INDEX_ENTRY = "{INDEX_ENTRY_{MARKUP} {__ARG__}}"

GLOBAL.INDEX_ENTRY_text = function (context, arg)
  arg = strsubst(context, arg)
  local firstchar=arg:sub(1,1):lower()

  if lastfirstchar ~= firstchar then
    lastfirstchar = firstchar
    return strsubst(context, firstchar:upper()..":{NL}  "..arg.."{NL}")
  else
    return strsubst(context, "  "..arg.."{NL}")
  end
end

GLOBAL.INDEX_ENTRY_asciidoc = function (context, arg)
  arg = strsubst(context, arg)
  local firstchar = arg:sub(1,1):lower()

  if lastfirstchar ~= firstchar then
    lastfirstchar = firstchar
    return strsubst(context, "{NL}[big]#"..firstchar:upper().."# :: {NL}   <<index_"..arg..","..arg..">> :::")
  else
    return strsubst(context, "  <<index_"..arg:gsub("%W","_")..","..arg..">> :::")
  end
end

GLOBAL.INDEX_ENTRY_orgmode = function (context, arg)
  arg = strsubst(context, arg)
  local firstchar = arg:sub(1,1):lower()

  if lastfirstchar ~= firstchar then
    lastfirstchar = firstchar
    return strsubst(context, "{NL} - *"..firstchar:upper().."* ::{NL}   <<index_"..arg..">>{LINEBREAK}")
  else
    return strsubst(context, "  <<index_"..arg:gsub("%W","_")..">>{LINEBREAK}")
  end
end



--shipped_config_post:
--: * Keep track of original file:line as asciidoc comments in the output.
--:   Disable this tracking when a doc comment starts with 'NOORIGIN' and
--:   re-enable it with a doc comment starting with 'ORGIN'.
local file
local line=0
local origin=true

postprocessor_register (nil,
                        function (context)
                          if context.TEXT:match("^NOORIGIN") then
                            origin=false
                            return false
                          end
                          return true
                        end
)

postprocessor_register (nil,
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




--shipped_config_pre:
--: * When GLOBAL.ISSUES is defined, generate formatted lists for doc comments in
--:   WIP/FIXME/TODO/PLANNED/DONE sections.
--:   When GLOBAL.GIT is defined ('-D GIT') then each such item includes information gathered
--:   from the git commit which touched that line the last.
--:   When GLOBAL.NOBUG is defined it reaps http://nobug.pipapo.org[NoBug] annotations from
--:   C source files as well.
if GLOBAL.GIT then

  --shipped_config_subst:
  --: {MACRODEF GIT_BLAME}
  --: Inserts a 'git blame' report about the current line.
  --: Refer to the source for details.
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

    return strsubst(context, "{GIT_BLAME_{MARKUP}}")
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

if GLOBAL.ISSUES then
  preprocessor_register (nil,
                         function (context)
                           for _,word in ipairs(issues_keywords) do
                             for _,comment in ipairs(context.COMMENTS_TABLE) do
                               local ret, matches = context.SOURCE:gsub(
                                 "("..pattern_escape (comment)..word..")(:%S*)%s?(.*)",
                                 '%1%2_ISSUE {FILE}:{LINE}::{NL}  %3{GIT_BLAME}', 1)
                               if matches > 0 then
                                 return ret
                               end
                             end
                           end
                           return true
                         end
  )
  preprocessor_register (nil,
                         function (context)
                           for _,word in ipairs(issues_keywords) do
                             for _,comment in ipairs(context.COMMENTS_TABLE) do
                               local ret, matches = context.SOURCE:gsub(
                                 "("..pattern_escape (comment)..word..")(%+%S*)%s?(.*)",
                                 '%1%2_ISSUE {LINEBREAK}  %3', 1)
                               if matches > 0 then
                                 return ret
                               end
                             end
                           end
                           return true
                         end
  )
end

-- for the testsuite
if GLOBAL.TESTSUITE then
  GLOBAL.STRING = "example string"
  GLOBAL.STR = "{STRING}"
  GLOBAL.ING = "ING"
  GLOBAL.UPR = "UPPER"
  GLOBAL.ARGTEST = "before {__ARG__} after"
  GLOBAL.UPPER = function(context, arg)
    arg = strsubst(context, arg)
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

--PLANNED: standard macros SAFE_MODE, LUA, SHELL, SET

--PLANNED: offer different sort orders for issues (date / line)
--PLANNED: noweb like preprocessing syntax for chapter substitutions in textfiles
--PLANNED: check that issues are unique
--PLANNED: ldoc/doxygen/javadoc compatible macros @param @return @see etc.

--- Local Variables:
--- mode: lua
--- compile-command: "lua pipadoc.lua --eissues"
--- End:
