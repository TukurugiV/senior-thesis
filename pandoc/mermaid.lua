-- mermaid.lua
-- Pandoc Lua filter:
--   - Detect fenced code blocks with class "mermaid"
--   - Render them via mermaid-cli (mmdc) into SVG (default) or PNG
--   - Replace the code block with an Image element
--
-- Requirements:
--   npm i -g @mermaid-js/mermaid-cli
-- Usage:
--   pandoc input.md -o output.pdf --lua-filter=mermaid.lua
--   pandoc input.md -o output.html --lua-filter=mermaid.lua

local system = pandoc.system
local utils  = pandoc.utils

-- Output format: "svg" or "png"
-- Use PNG for xelatex (SVG not supported)
local OUT_FMT = os.getenv("MERMAID_FORMAT") or "png"

-- Directory to store generated images
-- Use absolute path to ensure it works from any working directory
local OUT_DIR = "v:/卒研関係/mermaid"

-- mermaid-cli executable
local MMDC = os.getenv("MERMAID_MMDC") or "v:\\home\\tarou\\.npm-global\\mmdc.cmd"

-- Ensure output directory exists
local function ensure_dir(path)
  if system and system.make_directory then
    system.make_directory(path, true)
  else
    -- Fallback: use mkdir (works on both Windows and Unix)
    -- Windows uses 'mkdir', Unix uses 'mkdir -p'
    local is_windows = package.config:sub(1,1) == '\\'
    if is_windows then
      os.execute(string.format('if not exist "%s" mkdir "%s"', path, path))
    else
      os.execute(string.format('mkdir -p "%s"', path))
    end
  end
end

-- Stable file name from content (avoid regenerating same diagram)
local function sha1_hex(s)
  -- pandoc.utils.sha1 exists on modern Pandoc
  if utils and utils.sha1 then
    return utils.sha1(s)
  end
  -- Fallback: very simple (not cryptographic) hash if sha1 is unavailable
  local h = 2166136261
  for i = 1, #s do
    h = (h ~ s:byte(i)) * 16777619
    h = h % 4294967296
  end
  return string.format("%08x", h)
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function write_file(path, content)
  local f = assert(io.open(path, "wb"))
  f:write(content)
  f:close()
end

local function render_mermaid_to_image(code)
  ensure_dir(OUT_DIR)

  local hash = sha1_hex(code)
  local in_path  = OUT_DIR .. "/" .. hash .. ".mmd"
  local out_path = OUT_DIR .. "/" .. hash .. "." .. OUT_FMT

  -- If already rendered, reuse
  if file_exists(out_path) then
    return out_path
  end

  write_file(in_path, code)

  -- Build command:
  -- mmdc -i in.mmd -o out.svg
  -- Note: For PNG you may want puppeteer/Chrome environment; SVG is typically safest.
  local cmd = string.format('%s -i "%s" -o "%s"', MMDC, in_path, out_path)
  local ok = os.execute(cmd)

  -- os.execute return varies by platform; treat non-nil/0 as success loosely
  if ok == nil or ok == false then
    io.stderr:write("[mermaid.lua] Failed to run mmdc. Command:\n  " .. cmd .. "\n")
    return nil
  end

  if not file_exists(out_path) then
    io.stderr:write("[mermaid.lua] mmdc ran but output not found: " .. out_path .. "\n")
    return nil
  end

  return out_path
end

function CodeBlock(el)
  -- Pandoc parses ```mermaid as CodeBlock with class "mermaid"
  local is_mermaid = false
  for _, c in ipairs(el.classes) do
    if c == "mermaid" then
      is_mermaid = true
      break
    end
  end
  if not is_mermaid then
    return nil
  end

  local out_path = render_mermaid_to_image(el.text)
  if not out_path then
    -- If rendering fails, keep the original code block
    return el
  end

  -- Alt text: try to use an attribute "caption" if present, else default
  local caption = el.attributes["caption"] or "diagram"

  -- Return an Image block (as a Para containing an Image)
  local img = pandoc.Image(caption, out_path)
  return pandoc.Para({img})
end
