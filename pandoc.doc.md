---
title: "光学式モーションキャプチャ補助デバイスの開発"
author: "中野晃聖"
date: "2026年1月30日"
affiliation: "宇部工業高等専門学校 制御情報工学科"
lang: ja
mainfont: "Harano Aji Mincho"
figPrefix: "図"
figureTitle: "図"
tblPrefix: "表"
tableTitle: "表"
eqnPrefix: "式"
secPrefix: "節"
lstPrefix: "リスト"
output:
  pdf_document:
    pdf_engine: xelatex
    path: sample_paper.pdf
    include-in-header: pandoc/header.tex
    mainfont: "Noto Sans CJK JP"
export_on_save:
  pdf: true
geometry:
  - top=20mm
  - bottom=20mm
  - left=15mm
  - right=15mm
---

:::cover
:::

# Pandoc + Custom Lua Filter 記法リファレンス

このドキュメントでは、Pandocおよび独自のLuaフィルター（`paper-filter.lua`）を使用した論文執筆用の記法を解説します。
基本的には**Pandoc Markdown**に準拠しており、`pandoc-crossref`フィルターと併用することを想定しています。

---

## 1. 文書メタデータ (YAML Frontmatter)

ファイルの先頭にYAML形式でメタデータを記述します。これらは表紙生成(`:::cover`)に使用されます。

```yaml
---
title: "論文タイトル"
author: "著者名"
affiliation: "所属機関"
date: "202x年x月"
---
```

---

## 2. 独自拡張記法 (Custom Syntax)

`paper-filter.lua` によって処理される独自の記法です。

### 2.1 表紙 (Cover)

メタデータの内容を用いて、論文の表紙を生成します。
LaTeX/PDF出力時は `\begin{titlepage}` 環境、HTML出力時は全画面のカバーページとしてレンダリングされます。

**記法:**
```markdown
:::cover
:::
```

### 2.2 学術系環境 (Environments)

定理、証明、定義などの環境を構築するために `:::Type Title` 形式のfenced divsを使用します。
LaTeX出力時は `tcolorbox` または `amsthm` 環境に、HTML出力時はスタイル付きの `div` に変換されます。

**基本構文:**
```markdown
:::EnvType タイトル
内容...
:::
```

**使用可能な環境一覧:**

| 環境名 (EnvType) | 日本語名     | LaTeX環境  | 用途                     |
| :--------------- | :----------- | :--------- | :----------------------- |
| `theorem`        | 定理         | theorem    | 定理の記述               |
| `lemma`          | 補題         | lemma      | 補題の記述               |
| `definition`     | 定義         | definition | 用語の定義               |
| `example`        | 例           | example    | 具体例の提示             |
| `algorithm`      | アルゴリズム | algorithm  | アルゴリズムの説明       |
| `note`           | 注           | note       | 注釈、補足               |
| `warning`        | 警告         | warning    | 注意喚起                 |
| `proof`          | 証明         | proof      | 証明の記述 (末尾に□付与) |

**使用例:**

```markdown
:::theorem ピタゴラスの定理
直角三角形において、斜辺の2乗は他の2辺の2乗の和に等しい。
:::

:::proof
$a^2 + b^2 = c^2$ であることを示す。
（証明略）
:::

:::algorithm バブルソート
1. 配列の先頭から順に隣接要素を比較
2. 順序が逆なら交換
3. 配列末尾まで繰り返す
:::
```

### 2.3 ページ区切り (Page Break)

強制的に改ページを行います。
LaTeX/PDF出力時は `\newpage`、HTML出力時は `page-break-after: always` に変換されます。

**記法1 (Fenced Div):**
```markdown
:::page-break
:::
```

**記法2 (HTMLタグ - 互換性のため):**
```html
<div class="page-break"></div>
```

### 2.4 表記法拡張 (Table Extension)

表のキャプションを記述するための拡張記法です。`pandoc-crossref` が認識可能な形式に正規化されます。

**記法:**
```markdown
[Table: キャプション]{#tbl:ラベル}
```

**例:**
```markdown
[Table: 実験結果の比較]{#tbl:results}

| 手法     | 精度 |
| :------- | :--- |
| 提案手法 | 95%  |
| 従来手法 | 80%  |
```
↓ 内部的に以下のように変換され、`pandoc-crossref` で処理されます。
```markdown
: 実験結果の比較 {#tbl:results}

| 手法 | 精度 |
...
```

---

## 3. 標準 Pandoc / Pandoc-crossref 記法

以下は標準的なPandocまたは標準的なプラグイン（pandoc-crossref）の機能ですが、併せてよく使用されます。

### 3.1 図 (Figures)

画像埋め込み時に `{}` でIDを指定することで、図番号とキャプションが付きます。

**定義:**
```markdown
![システム構成図](./images/system.png){#fig:system}
```

**参照:**
```markdown
[@fig:system] にシステム構成を示す。
```

### 3.2 表 (Tables)

**定義:**
標準的なMarkdownの表の直前（または直後）にキャプションを置きます。独自記法を使わない場合は以下のように書けます。

```markdown
| A   | B   |
| --- | --- |
| 1   | 2   |

: 表のキャプション {#tbl:sample}
```

**参照:**
```markdown
詳細は [@tbl:sample] を参照。
```

### 3.3 数式 (Equations)

**定義:**
`$$` で囲み、末尾に `{#eq:label}` を付与します。

```markdown
$$
E = mc^2
$$ {#eq:einstein}
```

**参照:**
```markdown
[@eq:einstein] より導かれる。
```
