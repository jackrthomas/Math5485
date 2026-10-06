-- Render equation cross-references as (n.m) instead of "Equation n.m"
function Link(el)
  if el.target:match("^#eq%-") then
    return { pandoc.Str("("), el, pandoc.Str(")") }
  end
end

function RawInline(el)
  if el.format == "latex" and el.text:match("^\\ref{eq%-") then
    return pandoc.RawInline("latex", el.text:gsub("^\\ref", "\\eqref"))
  end
end
