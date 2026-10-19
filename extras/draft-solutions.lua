-- Hints/solutions marked .draft (written but not yet checked) only appear in the private build:
--   ::: {.exercise-solution .draft style="display: none;"}
-- Remove the .draft class once you have checked it to make it public.
local function is_private()
  local p = quarto.project and quarto.project.profile
  if p then
    for _, v in ipairs(p) do
      if pandoc.utils.stringify(v) == 'private' then return true end
    end
  end
  return (os.getenv('QUARTO_PROFILE') or ''):match('private') ~= nil
end

function Div(el)
  if el.classes:includes('draft') and not is_private() then
    return {}
  end
end
