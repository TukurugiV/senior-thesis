--[[
  引用上付き変換フィルター
  citeprocの後に実行される必要がある

  citeprocが生成した [番号] 形式の引用を検出し、
  括弧ごと上付き文字に変換する
]]

---@diagnostic disable: undefined-global

local OUTPUT_FORMAT = FORMAT or "html"

-- 引用リンクかどうかを判定
local function is_citation_link(el)
  return el.t == "Link" and el.target:match("^#ref%-")
end

-- Inlinesを処理して引用パターンを上付きに変換
function Inlines(inlines)
  local result = pandoc.List()
  local i = 1

  while i <= #inlines do
    local el = inlines[i]

    -- "["で終わるStrを検出（引用の開始候補）
    if el.t == "Str" and el.text:match("%[$") then
      local next_idx = i + 1

      -- 次の要素が引用リンクかチェック
      if next_idx <= #inlines and is_citation_link(inlines[next_idx]) then
        -- 引用パターンの開始を検出
        local prefix = el.text:match("^(.*)%[$")
        if prefix and prefix ~= "" then
          result:insert(pandoc.Str(prefix))
        end

        -- 引用コンテンツを収集（閉じ括弧まで）
        local latex_parts = {}
        local html_parts = {}
        table.insert(latex_parts, "[")
        table.insert(html_parts, "[")

        local j = next_idx
        local found_close = false

        while j <= #inlines do
          local inner = inlines[j]

          if is_citation_link(inner) then
            -- Pandocの標準Link処理を使用してLaTeX出力を取得
            local link_doc = pandoc.Pandoc({pandoc.Plain({inner})})
            local link_latex = pandoc.write(link_doc, "latex")
            link_latex = link_latex:gsub("[\n\r]", "") -- 改行を除去
            table.insert(latex_parts, link_latex)

            local content = pandoc.utils.stringify(inner)
            table.insert(html_parts, '<a href="' .. inner.target .. '">' .. content .. '</a>')
          elseif inner.t == "Str" then
            if inner.text:match("^%]") then
              -- 閉じ括弧を検出
              table.insert(latex_parts, "]")
              table.insert(html_parts, "]")

              local suffix = inner.text:match("^%](.*)$")

              -- 上付きで出力
              if OUTPUT_FORMAT:match("latex") or OUTPUT_FORMAT:match("pdf") then
                local citation_text = table.concat(latex_parts)
                result:insert(pandoc.RawInline("latex", "\\textsuperscript{" .. citation_text .. "}"))
              else
                local citation_text = table.concat(html_parts)
                result:insert(pandoc.RawInline("html", "<sup>" .. citation_text .. "</sup>"))
              end

              if suffix and suffix ~= "" then
                result:insert(pandoc.Str(suffix))
              end

              i = j
              found_close = true
              break
            else
              -- カンマや他のテキスト
              table.insert(latex_parts, inner.text)
              table.insert(html_parts, inner.text)
            end
          elseif inner.t == "Space" then
            table.insert(latex_parts, " ")
            table.insert(html_parts, " ")
          end
          j = j + 1
        end

        if not found_close then
          -- 閉じ括弧が見つからなかった、元の要素を追加
          result:insert(el)
        end
      else
        result:insert(el)
      end
    else
      result:insert(el)
    end

    i = i + 1
  end

  return result
end
