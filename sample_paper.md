---
document_year: "令和xx年度"
document_type: "document_type"
title: "document_title"
student_id: "student_id"
author: "your_name"
affiliation: "course"
supervisor: "teacher"
date: "yyyy年mm月dd日"
lang: ja
indent: true
mainfont: "Harano Aji Mincho"
linestretch: 1.25
parskip: 0.5em
figPrefix: "図"
figureTitle: "図"
figureIndexTemplate: "$$i$$"
figurePrefixTemplate: "$$p$$ $$i$$"
tblPrefix: "表"
tableTitle: "表"
tableIndexTemplate: "$$i$$"
tablePrefixTemplate: "$$p$$ $$i$$"
eqnPrefix: "式"
eqnIndexTemplate: "$$i$$"
eqnPrefixTemplate: "$$p$$ $$i$$"
secPrefix: "第"
lstPrefix: "リスト"
listingTitle: "リスト"
codeBlockCaptions: true
output:
  pdf_document:
    pdf_engine: xelatex
    path: sample_paper.pdf
    include-in-header: pandoc/header.tex
    mainfont: "Noto Sans CJK JP"
    number_sections: true
    toc: false
    pandoc_args:
      - "--lua-filter=pandoc/mermaid.lua"
      - "--lua-filter=pandoc/paper-filter.lua"
      - "--filter=pandoc-crossref"
      - "--citeproc"
      - "--bibliography=references.bib"
      - "--csl=japanese-reference.csl"
      - "--lua-filter=pandoc/cite-superscript.lua"
      - "--number-sections"
      - "-M"
      - "numberSections=true"
      - "-M"
      - "link-citations=true"
export_on_save:
  pdf: true
geometry:
  - top=30mm
  - bottom=30mm
  - left=20mm
  - right=20mm
  - headheight=15pt
  - headsep=10mm
  - footskip=12mm
---

<style>
p {
  padding-left: 1em;
  text-indent: -1em;
}
li > p {
  padding-left: 0;
  text-indent: 0;
}
</style>

:::cover
:::

\tableofcontents
\newpage

# 見出し1(第n章で表示される)
## 見出し2 (1.1 のように表示される)
### 見出し3 (1.1.1 のように表示される)

# 各種記法

## 画像

### 記法(基本)
画像に関して[@fig:image1]で自動で番号付けされて参照可能．

```md
![イメージ画像1](image1.jpg){#fig:image1}
```
### 見え方(基本)
![イメージ画像1](image1.jpg){#fig:image1}

### 記法(複数画像1)

複数の画像を並べることもできる．
このとき，画像の横幅を決めることができる

```md
::: {.figures}
![イメージ画像1](image1.jpg){#fig:image1_1 width=40%}
![イメージ画像2](image2.jpg){#fig:image1_2 width=40%}
:::
```

### 見え方(複数画像1)
::: {.figures}
![イメージ画像1](image1.jpg){#fig:image1_1 width=40%}
![イメージ画像2](image2.jpg){#fig:image1_2 width=40%}
:::

### 記法(複数画像2)
複数の画像を並べるときの，横の数を決めることもできる．

```md
::: {.figures cols=2}
![イメージ画像1](image1.jpg){#fig:image1_1}
![イメージ画像2](image2.jpg){#fig:image1_2}
![イメージ画像2](image3.jpg){#fig:image1_2}
![イメージ画像2](image4.jpg){#fig:image1_2}
:::
```

### 記法(複数画像2)
::: {.figures cols=2}
![イメージ画像1](image1.jpg){#fig:image1_1}
![イメージ画像2](image2.jpg){#fig:image1_2}
![イメージ画像2](image3.jpg){#fig:image1_2}
![イメージ画像2](image4.jpg){#fig:image1_2}
:::

### 記法(複数画像3)
高さを決めることもできる

```md
::: {.figures height=5cm}
![イメージ画像1](image1.jpg){#fig:image1_1}
![イメージ画像2](image2.jpg){#fig:image1_2}
![イメージ画像2](image3.jpg){#fig:image1_2}
![イメージ画像2](image4.jpg){#fig:image1_2}
:::
```

### 記法(複数画像4)
::: {.figures height=5cm}
![イメージ画像1](image1.jpg){#fig:image1_1}
![イメージ画像2](image2.jpg){#fig:image1_2}
![イメージ画像2](image3.jpg){#fig:image1_2}
![イメージ画像2](image4.jpg){#fig:image1_2}
:::

## 改ページ
### 記法
(次のページに行きます)
```md
:::page-break
:::
```

:::page-break
:::

## ファイルインポート
### 記法
```
@import "./sample.py"
```

### 見え方
@import "./sample.py"


## 表
### 記法
```
| 手法     | 精度 |
| :------- | :--- |
| 提案手法 | 95%  |
| 従来手法 | 80%  |

: 実験結果の比較 {#tbl:results}

[@tbl:results]に記す．
```

### 見え方
| 手法     | 精度 |
| :------- | :--- |
| 提案手法 | 95%  |
| 従来手法 | 80%  |

: 実験結果の比較 {#tbl:results}

[@tbl:results]に記す．

## 数式
### 記法
```
$$
\int_0^1 f(x) dx.
$${#eq:formula}

式は[@eq:formula]のとおりである．
```

### 見え方

$$
\int_0^1 f(x) dx.
$${#eq:formula}

式は[@eq:formula]のとおりである．

## 参考文献/参照
### 記法
references.bibにて
```references.bib
@article{article_pattern_recognition,
  title={Pattern Recognition and Machine Learning},
  author={Christopher M. Bishop},
  year={2006},
  url={https://www.microsoft.com/en-us/research/wp-content/uploads/2006/01/Bishop-Pattern-Recognition-and-Machine-Learning-2006.pdf}
}
```
markdown内にて
```
～がニューラルネットワークである[@article_pattern_recognition]．

::: {#refs}
:::
```

### 見え方

～がニューラルネットワークである[@article_pattern_recognition]．

::: {#refs}
:::

## mermaid
### 記法
```
`` `mermaid
sequenceDiagram
participant PC as レンダリング用コンピュータ
    participant O as OptiTrack eSync2
    participant R as Seeed Studio XIAO nRF52840 受信用デバイス
    participant T as Seeed Studio XIAO nRF52840 送信用デバイス

    %% 初期同期
    O->>R: 立ち上がりパルス（1回）
    R->>R: カウント初期化

    %% フレーム同期（120fps）
    loop フレーム同期（120fps）
        O->>R: 露光同期パルス
        R->>R: カウントアップ

        %% 無線同期
        R->>T: リクエスト（カウント）
        T-->>R: ジャイロデータ（同一カウント）

        %% PCへの送信
        R-->>PC: ジャイロデータ（カウント付き）

        %% モーションデータ
        O-->>PC: モーションデータ（OptiTrack）
    end
`` `
```

### 見え方
```mermaid
sequenceDiagram
    participant User
    participant Frontend
    participant Backend
    participant Database

    User->>Frontend: 操作要求
    Frontend->>Backend: APIリクエスト
    Backend->>Database: データ取得
    Database-->>Backend: 取得結果
    Backend-->>Frontend: レスポンス
    Frontend-->>User: 画面更新
```

## 目次
### 記法
```
\tableofcontents
```

### 見え方
1ページ目を参照のこと
