-- slide-wrap.lua
-- Supports:
--  • H2 slides with normal body → wrap body in <div class="slide-content ...">
--  • H2 slides with {.title-center} → emit ONLY the H2 (no slide-content; center via CSS)
--  • '---' (HorizontalRule) → title-less slide; wrap body in <div class="slide-content full">
--  • Image-only paragraphs → <div class="img-wrap ..."><img ...></div>

-- Treat these classes as wrapper classes (moved from <img> to .img-wrap)
local WRAP_CLASS = { center=true, contain=true, cover=true, ["abs-center"]=true }
local function is_wrap_class(c)
  return WRAP_CLASS[c] or c:match("^h%-%d+$") or c:match("^w%-%d+$")
end

local function image_only_para(b)
  if b.t ~= "Para" then return nil end
  local inl = b.content
  if #inl ~= 1 then return nil end
  local el = inl[1]
  if el.t ~= "Image" then return nil end
  return el
end

local function split_classes(classes)
  local to_wrapper, to_img = {}, {}
  for _, c in ipairs(classes or {}) do
    if is_wrap_class(c) then table.insert(to_wrapper, c) else table.insert(to_img, c) end
  end
  return to_wrapper, to_img
end

local function wrap_block_if_image_only(nb)
  local img = image_only_para(nb)
  if not img then return nb end

  local wrap_classes, keep_on_img = split_classes(img.attr.classes or {})
  local h_attr = img.attr.attributes and img.attr.attributes["height"] or nil
  local w_attr = img.attr.attributes and img.attr.attributes["width"]  or nil

  img.attr.classes = keep_on_img
  img.attr.attributes = img.attr.attributes or {}
  img.attr.attributes["height"] = nil
  img.attr.attributes["width"]  = nil
  local s = img.attr.attributes["style"] or ""
  img.attr.attributes["style"] =
    (s ~= "" and s .. " " or "") .. "display:block;max-width:100%;max-height:100%;"

  local wclasses = {"img-wrap"}
  for _, c in ipairs(wrap_classes) do table.insert(wclasses, c) end
  local wattr = pandoc.Attr("", wclasses)
  wattr.attributes = wattr.attributes or {}
  local wstyle = ""
  if h_attr and h_attr ~= "" then wstyle = wstyle .. "height:" .. h_attr .. ";" end
  if w_attr and w_attr ~= "" then wstyle = wstyle .. "width:"  .. w_attr .. ";" end
  if wstyle ~= "" then wattr.attributes["style"] = wstyle end

  return pandoc.Div({ pandoc.Plain{img} }, wattr)
end

-- Slide state
local cur_header    = nil           -- Header(2) or nil
local cur_classes   = nil           -- classes for .slide-content
local cur_is_full   = false         -- title-less slide (after ---)
local cur_title_only= false         -- H2 {.title-center} → emit H2 only
local cur_content   = pandoc.List() -- collected blocks

local function ensure_full(classes)
  local has = false
  for _, c in ipairs(classes) do if c == "full" then has = true; break end end
  if not has then table.insert(classes, "full") end
  return classes
end

local function flush_slide(out)
  local has_any = (cur_header ~= nil) or (#cur_content > 0)
  if not has_any then return end

  if cur_title_only and cur_header then
    -- Emit ONLY the header; no slide-content
    out:insert(cur_header)
  else
    if cur_header then out:insert(cur_header) end
    local classes = cur_classes or {"slide-content"}
    if cur_is_full then classes = ensure_full(classes) end
    out:insert(pandoc.Div(cur_content, pandoc.Attr("", classes)))
  end

  -- reset
  cur_header     = nil
  cur_classes    = nil
  cur_is_full    = false
  cur_title_only = false
  cur_content    = pandoc.List()
end

function Pandoc(doc)
  local out = pandoc.List()
  local i = 1
  while i <= #doc.blocks do
    local b = doc.blocks[i]

    if b.t == "Header" and b.level == 2 then
      -- New titled slide
      flush_slide(out)
      cur_header     = b
      cur_is_full    = false
      cur_title_only = false

      -- If header has .title-center → header-only slide
      local classes = b.attr and b.attr.classes or {}
      for _, c in ipairs(classes) do
        if c == "title-center" then
          cur_title_only = true
          break
        end
      end

      -- If not title-only, prep slide-content with inherited classes
      if not cur_title_only then
        cur_classes = {"slide-content"}
        for _, c in ipairs(classes) do table.insert(cur_classes, c) end
      end

    elseif b.t == "HorizontalRule" then
      -- '---' → title-less slide
      flush_slide(out)
      out:insert(b) -- keep HR so Reveal makes a slide break
      cur_header     = nil
      cur_is_full    = true
      cur_title_only = false
      cur_classes    = {"slide-content", "full"}

    else
      -- Add content only if not a header-only slide
      if not cur_title_only then
        cur_content:insert(wrap_block_if_image_only(b))
      end
      -- If title-only, we intentionally discard any following blocks
      -- until the next slide boundary.
    end

    i = i + 1
  end

  flush_slide(out)
  doc.blocks = out
  return doc
end
