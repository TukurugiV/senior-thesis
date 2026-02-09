--[[
  論文向けPandoc Luaフィルター
  独自記法をLaTeX/PDF および HTML に変換

  対応記法:
  - :::cover - 表紙
  - [Table: キャプション]{#tbl:ラベル} - 表の定義（pandoc-crossref形式に変換）
  - <div class="page-break"></div> - ページ区切り
  - :::figures - 画像の横並びレイアウト
    - cols属性で列数指定（デフォルト: 画像数に応じて自動）
    - height属性でブロック全体のデフォルト高さを指定可能
    - 各画像にwidth属性で幅を指定可能
    - 各画像にheight属性で高さを指定可能（個別指定はブロック設定より優先）

  使用方法:
    pandoc input.md -o output.pdf --lua-filter=paper-filter.lua
    pandoc input.md -o output.html --lua-filter=paper-filter.lua
]]

-- Pandocが提供するグローバル変数（Lua LSP警告抑制用）
---@diagnostic disable: undefined-global

-- 出力フォーマットを取得
local OUTPUT_FORMAT = FORMAT or "html"

-- LaTeX特殊文字をエスケープする関数
local function escapeLatex(str)
  if not str then return "" end
  -- LaTeXの特殊文字をエスケープ
  str = str:gsub("\\", "\\textbackslash{}")
  str = str:gsub("&", "\\&")
  str = str:gsub("%%", "\\%%")
  str = str:gsub("%$", "\\$")
  str = str:gsub("#", "\\#")
  str = str:gsub("_", "\\_")
  str = str:gsub("{", "\\{")
  str = str:gsub("}", "\\}")
  str = str:gsub("~", "\\textasciitilde{}")
  str = str:gsub("%^", "\\textasciicircum{}")
  return str
end

-- メタデータを保持
local meta = {}

-- HTML用の図番号カウンター
local htmlFigureCounter = 0

-- 画像を収集するヘルパー関数
local function collectImages(blocks)
  local images = {}
  for _, block in ipairs(blocks) do
    if block.t == "Para" then
      for _, inline in ipairs(block.content) do
        if inline.t == "Image" then
          table.insert(images, inline)
        end
      end
    elseif block.t == "Plain" then
      for _, inline in ipairs(block.content) do
        if inline.t == "Image" then
          table.insert(images, inline)
        end
      end
    -- Pandoc 3.x: Figure ブロックから画像を収集
    elseif block.t == "Figure" then
      -- Figure の content から画像を取得
      if block.content then
        for _, subblock in ipairs(block.content) do
          if subblock.t == "Plain" or subblock.t == "Para" then
            for _, inline in ipairs(subblock.content) do
              if inline.t == "Image" then
                -- Figure のキャプションと識別子を Image に引き継ぐ
                if block.caption and block.caption.long then
                  local captionText = pandoc.utils.stringify(block.caption.long)
                  if captionText ~= "" then
                    inline.caption = block.caption.long[1].content or inline.caption
                  end
                end
                if block.identifier and block.identifier ~= "" then
                  inline.identifier = block.identifier
                end
                table.insert(images, inline)
              end
            end
          end
        end
      end
    end
  end
  return images
end

-- クラスリストから属性を抽出するヘルパー関数
-- :::figures {height=6cm cols=2} のような形式をパース
local function parseClassAttributes(classes, attributes)
  local attrs = {}
  -- 既存の属性をコピー
  for k, v in pairs(attributes) do
    attrs[k] = v
  end

  -- クラスリストから {key=value} 形式を探してパース
  for _, class in ipairs(classes) do
    -- {height=6cm} や {cols=2} のような形式をチェック
    if class:match("^{.*}$") then
      -- 中括弧を除去してkey=valueをパース
      local inner = class:sub(2, -2)
      for key, value in inner:gmatch("([%w_-]+)=([^%s}]+)") do
        attrs[key] = value
      end
    end
  end

  return attrs
end

-- 画像の横並びレイアウト処理
local function processFigures(el)
  local images = collectImages(el.content)
  local numImages = #images

  if numImages == 0 then
    return el
  end

  -- クラスリストから追加属性をパース（:::figures {height=6cm} 形式対応）
  local attrs = parseClassAttributes(el.classes, el.attributes)

  -- 属性からcols（列数）を取得、なければ画像数に応じて自動設定
  local cols = tonumber(attrs.cols) or numImages
  if cols > numImages then cols = numImages end

  -- ブロック全体のデフォルト高さを取得
  local defaultHeight = attrs.height

  if OUTPUT_FORMAT:match("latex") or OUTPUT_FORMAT:match("pdf") then
    -- LaTeX出力（minipage環境を使用、figure環境なし）
    local latex = "\n\\noindent\\begin{center}\n"

    -- 幅の計算（列間の余白を考慮）
    local defaultWidthPct = math.floor(90 / cols)

    for i, img in ipairs(images) do
      -- 画像の幅を属性から取得、なければ自動計算
      local widthPct = defaultWidthPct
      if img.attributes.width then
        local pct = img.attributes.width:match("(%d+)%%")
        if pct then
          widthPct = tonumber(pct) or defaultWidthPct
        end
      end
      local minipageWidth = string.format("%.2f\\textwidth", widthPct / 100)

      -- 画像の高さを属性から取得（個別指定 > ブロック全体のデフォルト）
      local heightOpt = ""
      local imgHeight = img.attributes.height or defaultHeight
      if imgHeight then
        heightOpt = ", height=" .. imgHeight
      end

      -- サブキャプションを取得
      local subCaption = pandoc.utils.stringify(img.caption)
      local subLabel = img.identifier or ""

      latex = latex .. "\\begin{minipage}[t]{" .. minipageWidth .. "}\n"
      latex = latex .. "\\centering\n"
      latex = latex .. "\\includegraphics[width=\\linewidth" .. heightOpt .. ", keepaspectratio]{" .. img.src .. "}\n"

      -- サブキャプションとラベル（ラベルがある場合は常に図番号を出力）
      if subLabel ~= "" then
        latex = latex .. "\\captionof{figure}{" .. subCaption .. "}"
        latex = latex .. "\\label{" .. subLabel .. "}"
        latex = latex .. "\n"
      elseif subCaption ~= "" then
        latex = latex .. "\\captionof{figure}{" .. subCaption .. "}\n"
      end
      latex = latex .. "\\end{minipage}"

      -- 列間のスペース
      if i < numImages then
        if i % cols == 0 then
          latex = latex .. "\n\n\\vspace{1em}\n\n"
        else
          latex = latex .. "\\hfill%\n"
        end
      else
        latex = latex .. "\n"
      end
    end

    latex = latex .. "\\end{center}\n"
    return pandoc.RawBlock("latex", latex)

  else
    -- HTML出力（flexboxを使用）
    local html = '<div class="figures" style="display: flex; flex-wrap: wrap; justify-content: center; gap: 1em; margin: 1em 0;">\n'
    local figWidthPct = math.floor(90 / cols)

    for _, img in ipairs(images) do
      -- 画像の幅を属性から取得
      local width = img.attributes.width or (figWidthPct .. "%")
      -- 画像の高さを属性から取得（個別指定 > ブロック全体のデフォルト）
      local imgHeight = img.attributes.height or defaultHeight
      local heightStyle = imgHeight and ("height: " .. imgHeight .. ";") or "height: auto;"
      local subCaption = pandoc.utils.stringify(img.caption)
      local subLabel = img.identifier or ""
      local labelAttr = subLabel ~= "" and (' id="' .. subLabel .. '"') or ""

      html = html .. '<figure style="flex: 0 0 ' .. width .. '; text-align: center; margin: 0;"' .. labelAttr .. '>\n'
      html = html .. '<img src="' .. img.src .. '" style="max-width: 100%; ' .. heightStyle .. ' object-fit: contain;">\n'
      -- ラベルがある場合は図番号を付ける
      if subLabel ~= "" then
        htmlFigureCounter = htmlFigureCounter + 1
        local figNum = "図" .. htmlFigureCounter
        if subCaption ~= "" then
          html = html .. '<figcaption style="font-size: 0.9em; margin-top: 0.5em;">' .. figNum .. ': ' .. subCaption .. '</figcaption>\n'
        else
          html = html .. '<figcaption style="font-size: 0.9em; margin-top: 0.5em;">' .. figNum .. '</figcaption>\n'
        end
      elseif subCaption ~= "" then
        html = html .. '<figcaption style="font-size: 0.9em; margin-top: 0.5em;">' .. subCaption .. '</figcaption>\n'
      end
      html = html .. '</figure>\n'
    end

    html = html .. '</div>'
    return pandoc.RawBlock("html", html)
  end
end

-- メタデータの取得
function Meta(m)
  -- メタデータを保存（文字列として）
  meta.document_year = m.document_year and pandoc.utils.stringify(m.document_year)
  meta.document_type = m.document_type and pandoc.utils.stringify(m.document_type)
  meta.title = m.title and pandoc.utils.stringify(m.title)
  meta.student_id = m.student_id and pandoc.utils.stringify(m.student_id)
  meta.author = m.author and pandoc.utils.stringify(m.author)
  meta.affiliation = m.affiliation and pandoc.utils.stringify(m.affiliation)
  meta.supervisor = m.supervisor and pandoc.utils.stringify(m.supervisor)
  meta.date = m.date and pandoc.utils.stringify(m.date)

  -- デフォルトのタイトル出力を抑制するためにメタデータを消去
  m.title = nil
  m.author = nil
  m.date = nil

  -- LaTeXヘッダーの注入（LaTeX/PDF出力時のみ）
  if OUTPUT_FORMAT:match("latex") or OUTPUT_FORMAT:match("pdf") then
    local latex_header = [[
% 論文向けLaTeXヘッダー

% 必要なパッケージ
\usepackage{graphicx}    % includegraphics コマンド用
\usepackage{caption}     % captionof コマンド用
]]
    local headers = m['header-includes'] or pandoc.MetaList({})
    -- header-includesが単体の要素かリストかで処理を分ける（通常はリスト）
    if type(headers) ~= 'table' then
       headers = pandoc.MetaList({headers})
    end
    table.insert(headers, pandoc.RawBlock('latex', latex_header))
    m['header-includes'] = headers
  end

  return m
end

-- Divの処理（fenced divs: :::xxx）
function Div(el)
  local classes = el.classes

  -- 表紙
  if classes:includes("cover") then
    local document_year = meta.document_year or ""
    local document_type = meta.document_type or ""
    local title = meta.title or ""
    local student_id = meta.student_id or ""
    local author = meta.author or ""
    local affiliation = meta.affiliation or ""
    local supervisor = meta.supervisor or ""
    local date = meta.date or ""

    if OUTPUT_FORMAT:match("latex") or OUTPUT_FORMAT:match("pdf") then
      local latex_content = pandoc.write(pandoc.Pandoc(el.content), "latex")
      -- 年度と文書タイプを結合（LaTeX特殊文字をエスケープ）
      local year_type = escapeLatex(document_year) .. " " .. escapeLatex(document_type)
      return pandoc.RawBlock("latex", string.format([[
\thispagestyle{empty}
\begin{center}
\vspace*{40mm}
{\huge\noindent %s}\\
\vspace{40mm}
{\huge\noindent %s}\\
\vspace{60mm}
\begin{tabular}{lr}
  \Large 学籍番号 & \Large %s \\
  \Large 氏名 & \Large %s \\
  \Large 所属学科 & \Large %s \\
  \Large 指導教員 & \Large %s \\
  \Large 日付 & \Large %s \\
\end{tabular}
\end{center}
%% Cover content start
%s
%% Cover content end
\clearpage
\setcounter{page}{1}
]], year_type, escapeLatex(title), escapeLatex(student_id), escapeLatex(author), escapeLatex(affiliation), escapeLatex(supervisor), escapeLatex(date), latex_content))
    else
      -- HTML出力（フルページ・中央揃え・枠線なし）
      local year_type = document_year .. " " .. document_type
      -- Divとして返すことで、Pandocの構造を維持
      local coverDiv = pandoc.Div({}, pandoc.Attr("", {"cover-rendered"}, {}))
      coverDiv.content = {
        pandoc.RawBlock("html", string.format([[
<div class="cover" style="display: flex; flex-direction: column; justify-content: center; align-items: center; text-align: center; min-height: 100vh; padding: 20mm; box-sizing: border-box;">
  <h2 style="font-size: 1.8em; margin-top: 40mm;">%s</h2>
  <h1 style="font-size: 2.2em; margin-top: 40mm;">%s</h1>
  <table style="margin-top: 60mm; font-size: 1.2em; border-collapse: collapse;">
    <tr><td style="text-align: left; padding: 0.3em 1em;">学籍番号</td><td style="text-align: left; padding: 0.3em 1em;">%s</td></tr>
    <tr><td style="text-align: left; padding: 0.3em 1em;">氏名</td><td style="text-align: left; padding: 0.3em 1em;">%s</td></tr>
    <tr><td style="text-align: left; padding: 0.3em 1em;">所属学科</td><td style="text-align: left; padding: 0.3em 1em;">%s</td></tr>
    <tr><td style="text-align: left; padding: 0.3em 1em;">指導教員</td><td style="text-align: left; padding: 0.3em 1em;">%s</td></tr>
    <tr><td style="text-align: left; padding: 0.3em 1em;">日付</td><td style="text-align: left; padding: 0.3em 1em;">%s</td></tr>
  </table>
</div>
]], year_type, title, student_id, author, affiliation, supervisor, date))
      }
      return coverDiv
    end
  end

  -- ページ区切り
  if classes:includes("page-break") then
    if OUTPUT_FORMAT:match("latex") or OUTPUT_FORMAT:match("pdf") then
      return pandoc.RawBlock("latex", "\\newpage")
    else
      return pandoc.RawBlock("html", '<div style="page-break-after: always;"></div>')
    end
  end

  -- 画像の横並びレイアウト（:::figures）
  if classes:includes("figures") then
    return processFigures(el)
  end

  return el
end

-- HTMLのRawBlockを処理（ページ区切り）
function RawBlock(el)
  -- HTML input (class="page-break") -> LaTeX output
  if el.format == "html" then
    if el.text:match('class="page%-break"') then
      if OUTPUT_FORMAT:match("latex") or OUTPUT_FORMAT:match("pdf") then
        return pandoc.RawBlock("latex", "\\newpage")
      else
        return pandoc.RawBlock("html", '<div style="page-break-after: always;"></div>')
      end
    end
  end

  -- LaTeX input (\newpage, \tableofcontents) -> HTML output
  if OUTPUT_FORMAT:match("html") and (el.format == "tex" or el.format == "latex") then
    if el.text:match("^\\newpage") or el.text:match("^\\pagebreak") then
      return pandoc.RawBlock("html", '<div style="page-break-after: always; border-top: 1px dashed #ccc; margin: 2em 0; text-align: center; color: #ccc;">--- Page Break ---</div>')
    end
    if el.text:match("^\\tableofcontents") then
       -- プレビュー用にメッセージを表示（実際のTOC生成は[TOC]記法を推奨）
      return pandoc.RawBlock("html", '<div style="border: 1px solid #ddd; background: #f9f9f9; padding: 1em; text-align: center; color: #666; margin: 1em 0;">(Table of Contents)</div>')
    end
  end

  return el
end

-- 表キャプション記法をパースする関数
-- [Table: キャプション]{#tbl:label} 形式を検出
-- Pandocによって Span 要素に変換されるため、Span要素から情報を取得
local function parseTableCaption(block)
  if block.t ~= "Para" then return nil end

  -- Para ブロック内の Span 要素を検索
  for _, inline in ipairs(block.content) do
    if inline.t == "Span" and inline.identifier and inline.identifier:match("^tbl:") then
      local text = pandoc.utils.stringify(inline.content)
      local caption = text:gsub("^Table:%s*", "")
      return { caption = caption, label = inline.identifier }
    end
  end
  return nil
end

-- 表カウンター
local tableCounter = 0

-- 表ラベルと番号のマッピング
local tableLabelMap = {}

-- 表とキャプションをLaTeXで出力
local function createTableWithCaptionLatex(tableBlock, captionInfo, tableNum)
  local tableContent = pandoc.write(pandoc.Pandoc({tableBlock}), "latex")

  -- longtable環境の場合はキャプションを先頭に挿入
  if tableContent:match("\\begin{longtable}") then
    -- longtable の開始直後にキャプションを挿入
    local captionLine = "\\caption{" .. captionInfo.caption .. "}\\label{" .. captionInfo.label .. "}\\\\\n"
    tableContent = tableContent:gsub(
      "(\\begin{longtable}%[[^%]]*%]\n)",
      "%1" .. captionLine
    )
    return pandoc.RawBlock("latex", tableContent)
  else
    -- 通常の表は table 環境でラップ
    local latex = "\\begin{table}[htbp]\n"
    latex = latex .. "\\centering\n"
    latex = latex .. "\\caption{" .. captionInfo.caption .. "}\\label{" .. captionInfo.label .. "}\n"
    latex = latex .. tableContent
    latex = latex .. "\\end{table}"
    return pandoc.RawBlock("latex", latex)
  end
end

-- 表とキャプションをHTMLで出力
local function createTableWithCaptionHtml(tableBlock, captionInfo, tableNum)
  local tableContent = pandoc.write(pandoc.Pandoc({tableBlock}), "html")

  local html = '<figure id="' .. captionInfo.label .. '" class="table-figure" style="margin: 1em 0;">\n'
  html = html .. '<figcaption style="text-align: center; font-weight: bold; margin-bottom: 0.5em;">表' .. tableNum .. ': ' .. captionInfo.caption .. '</figcaption>\n'
  html = html .. tableContent
  html = html .. '</figure>'
  return pandoc.RawBlock("html", html)
end

-- 表参照を解決する関数（Cite要素を処理）
local function resolveTableRefs(doc)
  local function resolveCite(el)
    if el.t == "Cite" then
      for _, citation in ipairs(el.citations) do
        local id = citation.id
        if id:match("^tbl:") and tableLabelMap[id] then
          local num = tableLabelMap[id]
          if OUTPUT_FORMAT:match("latex") or OUTPUT_FORMAT:match("pdf") then
            return pandoc.RawInline("latex", "表\\ref{" .. id .. "}")
          else
            return pandoc.Link({pandoc.Str("表" .. num)}, "#" .. id)
          end
        end
      end
    end
    return el
  end

  return doc:walk({Cite = resolveCite})
end

-- ドキュメント全体の処理（インデント設定を挿入 + 表キャプション処理）
function Pandoc(doc)
  local processed_blocks = {}
  local i = 1

  -- 表キャプションの処理（1回目のパス：表を処理してマッピングを作成）
  while i <= #doc.blocks do
    local block = doc.blocks[i]
    local captionInfo = parseTableCaption(block)

    if captionInfo then
      -- 次のブロックが表かチェック
      local nextBlock = doc.blocks[i + 1]
      if nextBlock and nextBlock.t == "Table" then
        -- 表番号をインクリメント
        tableCounter = tableCounter + 1
        -- ラベルと番号のマッピングを保存
        tableLabelMap[captionInfo.label] = tableCounter

        -- キャプション付き表を生成
        if OUTPUT_FORMAT:match("latex") or OUTPUT_FORMAT:match("pdf") then
          table.insert(processed_blocks, createTableWithCaptionLatex(nextBlock, captionInfo, tableCounter))
        else
          table.insert(processed_blocks, createTableWithCaptionHtml(nextBlock, captionInfo, tableCounter))
        end
        i = i + 2 -- キャプション行と表の両方をスキップ
      else
        -- 次のブロックが表でない場合はそのまま出力
        table.insert(processed_blocks, block)
        i = i + 1
      end
    else
      table.insert(processed_blocks, block)
      i = i + 1
    end
  end

  doc.blocks = processed_blocks

  -- 表参照を解決（2回目のパス）
  doc = resolveTableRefs(doc)

  -- LaTeX/PDF出力時の追加処理
  if OUTPUT_FORMAT:match("latex") or OUTPUT_FORMAT:match("pdf") then
    local final_blocks = {}
    -- ドキュメント本文の最初にインデント設定を挿入
    table.insert(final_blocks, pandoc.RawBlock("latex", "\\setlength{\\parindent}{1em}"))

    for _, block in ipairs(doc.blocks) do
      -- レベル1ヘッダー（章）の前に改ページを挿入
      if block.t == "Header" and block.level == 1 then
        table.insert(final_blocks, pandoc.RawBlock("latex", "\\clearpage"))
      end
      table.insert(final_blocks, block)
      -- ヘッダーの直後に\@afterindenttrue を挿入
      if block.t == "Header" then
        table.insert(final_blocks, pandoc.RawBlock("latex", "\\makeatletter\\@afterindenttrue\\makeatother"))
      end
    end
    doc.blocks = final_blocks
  end

  return doc
end

-- @import記法の処理（Markdown Preview Enhanced互換）
-- @import "ファイルパス" の形式でファイルを読み込む
function CodeBlock(el)
  return el
end

-- Paraブロック内の@import記法を処理
local function processImport(el)
  local text = pandoc.utils.stringify(el)

  -- @import "ファイルパス" パターンを検出
  local filePath = text:match('^@import%s+"([^"]+)"') or text:match("^@import%s+'([^']+)'")

  if filePath then
    -- ファイルを読み込む
    local file = io.open(filePath, "r")
    if file then
      local content = file:read("*all")
      file:close()

      -- ファイル拡張子を取得
      local ext = filePath:match("%.([^%.]+)$")
      if ext then
        ext = ext:lower()
      end

      -- 言語を拡張子から推測
      local lang = ""
      local langMap = {
        py = "python",
        js = "javascript",
        ts = "typescript",
        rb = "ruby",
        rs = "rust",
        c = "c",
        cpp = "cpp",
        h = "c",
        hpp = "cpp",
        java = "java",
        go = "go",
        lua = "lua",
        sh = "bash",
        bash = "bash",
        zsh = "zsh",
        ps1 = "powershell",
        yaml = "yaml",
        yml = "yaml",
        json = "json",
        xml = "xml",
        html = "html",
        css = "css",
        sql = "sql",
        md = "markdown",
        tex = "latex",
        toml = "toml",
        ino = "cpp"  -- Arduino
      }
      lang = langMap[ext] or ext or ""

      -- CodeBlockとして返す
      return pandoc.CodeBlock(content, {class = lang})
    else
      -- ファイルが見つからない場合はエラーメッセージを表示
      io.stderr:write("Warning: Could not open file: " .. filePath .. "\n")
      return pandoc.Para({pandoc.Strong({pandoc.Str("[Error: File not found: " .. filePath .. "]")})})
    end
  end

  return nil
end

-- Paraの処理を拡張（@import対応）
-- 注意: 表キャプションの処理は Pandoc 関数で行うため、ここでは変換しない
function Para(el)
  -- @importの処理を試みる
  local importResult = processImport(el)
  if importResult then
    return importResult
  end

  return el
end

-- フィルターの実行順序
return {
  {Meta = Meta},
  {Div = Div, RawBlock = RawBlock, Para = Para},
  {Pandoc = Pandoc}
}
