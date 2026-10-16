-- More difficult exercises: ::: {#exr-... .difficult}  or  ::: {#exr-... .difficult why="..."}
-- get a ◆ in the top-right corner of the exercise (lectures and exercise bank). Hovering or
-- tapping it shows "This exercise is more difficult", followed by `why` if given (markdown, so
-- maths works). The styles are in style.css ("More difficult exercises").
local TITLE = 'This exercise is more difficult'

function Div(el)
  local id = el.identifier
  if not (id:match('^exr%-') or id:match('^bank%-exr%-')) then return nil end
  if not el.classes:includes('difficult') then return nil end

  local why = el.attributes['why']
  el.attributes['why'] = nil
  if not quarto.doc.is_format('html') then return el end

  local tip = pandoc.List({ pandoc.Para({ pandoc.Strong({ pandoc.Str(TITLE) }) }) })
  if why and why:match('%S') then
    tip:extend(pandoc.read(why, 'markdown').blocks)
  end

  -- appended (not prepended) so the exercise title stays in the first paragraph
  el.content:insert(pandoc.Div({
    pandoc.Plain({ pandoc.Span({ pandoc.Str('◆') }, pandoc.Attr('', { 'exr-difficult-icon' }, { ['aria-hidden'] = 'true' })) }),
    pandoc.Div(tip, pandoc.Attr('', { 'exr-difficult-tip' }, { role = 'tooltip' })),
  }, pandoc.Attr('', { 'exr-difficult' }, { tabindex = '0', ['aria-label'] = TITLE })))
  return el
end
