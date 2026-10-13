-- ::: {.proof collapse="true"} → a collapsible <details> block (HTML only; ignored for PDF)
function Div(el)
  if not el.classes:includes('proof') or el.attributes['collapse'] ~= 'true' then
    return nil
  end
  if not quarto.doc.is_format('html') then
    return nil
  end
  el.attributes['collapse'] = nil
  -- keep the proof's name (e.g. name="non-examinable") in the summary line
  local summary = 'Proof'
  local name = el.attributes['name']
  if name and name ~= '' then
    summary = summary .. ' <span class="proof-name">(' .. name .. ')</span>'
  end
  return {
    pandoc.RawBlock('html', '<details class="proof-details"><summary>' .. summary .. '</summary>'),
    el,
    pandoc.RawBlock('html', '</details>')
  }
end
