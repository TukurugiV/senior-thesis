--[[
  論文向けPandoc Luaフィルター
  独自記法をLaTeX/PDF および HTML に変換

  対応記法:
  - :::cover - 表紙
  - :::theorem タイトル, :::proof, :::lemma タイトル, :::definition タイトル,
    :::example タイトル, :::note, :::algorithm タイトル, :::warning
  - [Table: キャプション]{#tbl:ラベル} - 表の定義（pandoc-crossref形式に変換）
  - <div class="page-break"></div> - ページ区切り

  使用方法:
    pandoc input.md -o output.pdf --lua-filter=paper-filter.lua
    pandoc input.md -o output.html --lua-filter=paper-filter.lua
]]

-- Pandocが提供するグローバル変数（Lua LSP警告抑制用）
---@diagnostic disable: undefined-global

-- 出力フォーマットを取得
local OUTPUT_FORMAT = FORMAT or "html"

-- メタデータを保持
local meta = {}

-- 環境タイプのリスト
-- tcolorbox newtcbtheorem形式: \begin{env}{タイトル}{ラベル}
local tcbTheoremEnv = {
  theorem = true,
  lemma = true,
  definition = true,
  example = true,
  algorithm = true
}

-- tcolorbox newtcolorbox形式: \begin{env}
local tcbBoxEnv = {
  note = true,
  warning = true
}

-- amsthm proof形式: \begin{proof}
local amsthmEnv = {
  proof = true
}

-- 環境の日本語名
local envNames = {
  theorem = "定理",
  lemma = "補題",
  definition = "定義",
  example = "例",
  algorithm = "アルゴリズム",
  note = "注",
  warning = "警告",
  proof = "証明"
}

-- 環境のスタイル（HTML用 - LaTeXライクなシンプルスタイル）
local envStyles = {
  theorem = "margin: 1em 0; font-family: serif;",
  lemma = "margin: 1em 0; font-family: serif;",
  definition = "margin: 1em 0; font-family: serif;",
  example = "margin: 1em 0; font-family: serif;",
  algorithm = "margin: 1em 0; font-family: serif;",
  note = "margin: 1em 0; font-family: serif;",
  warning = "margin: 1em 0; font-family: serif;",
  proof = "margin: 1em 0; font-family: serif;"
}

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
% カスタム環境の定義

% 必要なパッケージ
\usepackage{amsthm}

% 日本語用の環境名定義
\theoremstyle{definition}

% 定理環境
\newtheorem{theorem}{定理}[section]

% 補題環境
\newtheorem{lemma}{補題}[section]

% 定義環境
\newtheorem{definition}{定義}[section]

% 例環境
\newtheorem{example}{例}[section]

% アルゴリズム環境
\newtheorem{algorithm}{アルゴリズム}[section]

% 注釈環境（番号なし）
\theoremstyle{remark}
\newtheorem*{note}{注}

% 警告環境（番号なし）
\newtheorem*{warning}{警告}

% 証明環境（amsthmのデフォルトを使用、日本語化）
\renewcommand{\proofname}{証明}
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

-- クラスリストから環境タイプとタイトルを抽出
-- :::theorem ピタゴラスの定理 → type="theorem", title="ピタゴラスの定理"
local function extractEnvInfo(classes)
  local envType = nil
  local title = {}

  for i, class in ipairs(classes) do
    if i == 1 then
      -- 最初のクラスが環境タイプ
      if tcbTheoremEnv[class] or tcbBoxEnv[class] or amsthmEnv[class] then
        envType = class
      end
    else
      -- 残りのクラスはタイトルの一部（スペース区切り）
      table.insert(title, class)
    end
  end

  return envType, table.concat(title, " ")
end

-- LaTeX環境を生成
local function createLatexEnv(envName, title, content, envType)
  local latex_content = pandoc.write(pandoc.Pandoc(content), "latex")

  -- タイトルがある場合はオプション引数として追加
  local titleOpt = ""
  if title and title ~= "" then
    titleOpt = "[" .. title .. "]"
  end

  return pandoc.RawBlock("latex", string.format([[
\begin{%s}%s
%s
\end{%s}
]], envName, titleOpt, latex_content, envName))
end

-- HTML環境を生成
local function createHtmlEnv(envType, title, content)
  local html_content = pandoc.write(pandoc.Pandoc(content), "html")
  local envName = envNames[envType] or envType
  local style = envStyles[envType] or ""

  local titleHtml = ""
  if title and title ~= "" then
    titleHtml = string.format("<strong>%s: %s</strong><br>", envName, title)
  else
    titleHtml = string.format("<strong>%s</strong><br>", envName)
  end

  return pandoc.RawBlock("html", string.format([[
<div class="%s" style="%s">
%s%s
</div>
]], envType, style, titleHtml, html_content))
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
      -- 年度と文書タイプを結合
      local year_type = document_year .. " " .. document_type
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
]], year_type, title, student_id, author, affiliation, supervisor, date, latex_content))
    else
      -- HTML出力（フルページ・中央揃え・枠線なし）
      local year_type = document_year .. " " .. document_type
      return pandoc.RawBlock("html", string.format([[
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

  -- 環境タイプとタイトルを抽出
  local envType, title = extractEnvInfo(classes)

  if not envType then
    return el
  end

  -- 出力形式に応じて処理
  if OUTPUT_FORMAT:match("latex") or OUTPUT_FORMAT:match("pdf") then
    return createLatexEnv(envType, title, el.content, envType)
  else
    return createHtmlEnv(envType, title, el.content)
  end
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

-- Spanの処理（表のキャプション記法の変換）
function Span(el)
  if el.identifier and el.identifier:match("^tbl:") then
    local text = pandoc.utils.stringify(el.content)
    text = text:gsub("^Table:%s*", "")
    el.content = {pandoc.Str(text)}
    return el
  end
  return el
end

-- Paraの処理（独自の表記法を変換）
function Para(el)
  local text = pandoc.utils.stringify(el)

  if text:match("^%[Table:") or text:match("^%[") then
    local caption, label = text:match("^%[([^%]]+)%]%{#(tbl:[a-zA-Z0-9_-]+)%}")
    if caption and label then
      caption = caption:gsub("^Table:%s*", "")
      return pandoc.Para({
        pandoc.Str(": " .. caption .. " {#" .. label .. "}")
      })
    end
  end

  return el
end

-- ドキュメント全体の処理（インデント設定を挿入）
function Pandoc(doc)
  if OUTPUT_FORMAT:match("latex") or OUTPUT_FORMAT:match("pdf") then
    local new_blocks = {}
    -- ドキュメント本文の最初にインデント設定を挿入
    table.insert(new_blocks, pandoc.RawBlock("latex", "\\setlength{\\parindent}{1em}"))

    for i, block in ipairs(doc.blocks) do
      table.insert(new_blocks, block)
      -- ヘッダーの直後に\@afterindenttrue を挿入
      if block.t == "Header" then
        table.insert(new_blocks, pandoc.RawBlock("latex", "\\makeatletter\\@afterindenttrue\\makeatother"))
      end
    end
    doc.blocks = new_blocks
  end
  return doc
end

-- フィルターの実行順序
return {
  {Meta = Meta},
  {Div = Div, RawBlock = RawBlock, Para = Para, Span = Span},
  {Pandoc = Pandoc}
}
