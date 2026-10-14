-- Assemble the mdBook sources in SUMMARY order for Pandoc's Typst writer.
-- Run from docs/src; the website and PDF share the same authored Markdown.
local function read(path)
  local file = assert(io.open(path), 'cannot read ' .. path)
  local text = file:read('*a')
  file:close()
  return text
end

local function normalized(path)
  local parts = {}
  for part in path:gmatch('[^/]+') do
    if part == '..' and #parts > 0 and parts[#parts] ~= '..' then
      table.remove(parts)
    elseif part ~= '.' then
      parts[#parts + 1] = part
    end
  end
  return table.concat(parts, '/')
end

local function relative(page, target)
  return normalized(pandoc.path.directory(page) .. '/' .. target)
end

local function label(page, anchor)
  return page .. '#' .. (anchor or '')
end

function Pandoc()
  local entries, pages = {}, {}
  for line in read('SUMMARY.md'):gmatch('[^\n]+') do
    local part = line:match('^# (.+)')
    local indent, path = line:match('^(%s*)%-?%s*%[.-%]%((.-)%)')
    if path then
      entries[#entries + 1] = {page = path, depth = #indent // 2}
      pages[path] = true
    elseif part and part ~= 'Summary' then
      entries[#entries + 1] = {part = part}
    end
  end

  local blocks = pandoc.List()
  for _, entry in ipairs(entries) do
    if entry.part then
      blocks:insert(pandoc.Header(1, entry.part))
    else
      local page = entry.page
      local source = read(page):gsub('{{#include%s+(.-)}}', function(path)
        return read(relative(page, path))
      end)
      local document = pandoc.read(source, 'commonmark_x-smart')
      local first_heading = true
      local function anchor(raw)
        local id = raw.text:match('^<a id="([^"]+)">')
        if id then
          return pandoc.Span({}, pandoc.Attr(label(page, id)))
        end
      end
      document = document:walk({
        Header = function(h)
          h.identifier = label(page, h.identifier)
          h.level = h.level + entry.depth + 1
          if first_heading then
            first_heading = false
            h.content:insert(pandoc.Span({}, pandoc.Attr(h.identifier)))
            h.identifier = label(page)
          end
          return h
        end,
        RawBlock = function(raw)
          local span = anchor(raw)
          if span then return pandoc.Plain({span}) end
        end,
        RawInline = anchor,
        CodeBlock = function(code)
          local lang = (code.classes[1] or ''):match('^[^,]+')
          if lang == 'x2c' then
            local visible = {}
            for line in (code.text .. '\n'):gmatch('(.-)\n') do
              if not line:match('^%s*~') then visible[#visible + 1] = line end
            end
            code.text = table.concat(visible, '\n')
          end
          code.classes = {} -- Neutral, consistent print typography for all code.
          return code
        end,
        Link = function(link)
          local target = link.target
          if target:match('^%a[%w+.-]*:') or target:match('^//') then return end
          local path, fragment = target:match('^([^#]*)#?(.*)$')
          path = path == '' and page or relative(page, path)
          if pages[path] then
            link.target = '#' .. label(path, fragment)
          else
            -- Repository files outside the book remain useful online links.
            local repo_path = normalized('docs/src/' .. path)
            link.target = 'https://github.com/gwf/x2c/blob/dev/' .. repo_path
              .. (fragment ~= '' and '#' .. fragment or '')
          end
          return link
        end,
      })
      blocks:extend(document.blocks)
    end
  end
  return pandoc.Pandoc(blocks)
end
