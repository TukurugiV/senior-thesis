# 手動環境セットアップガイド

## 必要なツール一覧

| ツール | 用途 | 必須 |
|--------|------|------|
| Pandoc | Markdown→PDF変換 | Yes |
| XeLaTeX (TeX Live/TinyTeX) | PDF生成エンジン | Yes |
| pandoc-crossref | 図表・数式の相互参照 | Yes |
| 日本語フォント | 日本語表示 | Yes |
| Node.js + mermaid-cli | Mermaid図の描画 | No |

---

## 1. Pandoc のインストール

### ダウンロード
- 公式サイト: https://pandoc.org/installing.html
- GitHub: https://github.com/jgm/pandoc/releases

### Windows
```powershell
# wingetを使う場合
winget install --id JohnMacFarlane.Pandoc

# または Chocolatey
choco install pandoc
```

### 確認
```powershell
pandoc --version
```

---

## 2. LaTeX環境 のインストール

XeLaTeXが使用できるTeX環境が必要です。

### 選択肢A: TinyTeX（推奨・軽量）

```powershell
# PowerShellで実行
Invoke-WebRequest -Uri "https://yihui.org/tinytex/install-bin-windows.bat" -OutFile "install-tinytex.bat"
.\install-tinytex.bat
```

または GitHub から直接ダウンロード:
- https://github.com/rstudio/tinytex-releases/releases

### 選択肢B: TeX Live（フル環境）

- 公式サイト: https://www.tug.org/texlive/
- Windows用インストーラ: https://www.tug.org/texlive/acquire-netinstall.html

### 必要なLaTeXパッケージ

TinyTeXの場合、以下のパッケージを追加インストールしてください：

```powershell
tlmgr install xecjk ctex zxjafont haranoaji
tlmgr install fancyhdr geometry titlesec
tlmgr install hyperref bookmark
tlmgr install amsmath amssymb amsthm
tlmgr install graphicx float caption subcaption
tlmgr install booktabs longtable multirow
tlmgr install listings xcolor
tlmgr install ulem soul
tlmgr install etoolbox iftex unicode-math
tlmgr install fontspec luatexja
tlmgr install adjustbox collectbox
```

### 確認
```powershell
xelatex --version
```

---

## 3. pandoc-crossref のインストール

### ダウンロード
- GitHub: https://github.com/lierdakil/pandoc-crossref/releases

**重要**: Pandocのバージョンと互換性のあるバージョンを選択してください。

### インストール手順

1. リリースページから `pandoc-crossref-Windows-X64.7z` または `.zip` をダウンロード
2. 解凍して `pandoc-crossref.exe` を取得
3. PATHの通った場所に配置（例: Pandocと同じフォルダ）

### 確認
```powershell
pandoc-crossref --version
```

---

## 4. 日本語フォント のインストール

### 選択肢A: Harano Aji フォント（推奨）

TinyTeXの`haranoaji`パッケージに含まれています。

手動でインストールする場合：
- CTAN: https://ctan.org/pkg/haranoaji

```powershell
# TinyTeXの場合
tlmgr install haranoaji
```

フォントファイルの場所（TinyTeX）:
```
%APPDATA%\TinyTeX\texmf-dist\fonts\opentype\public\haranoaji\
```

### 選択肢B: Noto Sans CJK JP

- Google Fonts: https://fonts.google.com/noto/specimen/Noto+Sans+JP
- GitHub: https://github.com/notofonts/noto-cjk/releases

ダウンロード後、Windowsにフォントをインストールしてください。

### フォント確認
```powershell
# 利用可能なフォント一覧（XeLaTeX）
fc-list :lang=ja
```

---

## 5. Mermaid CLI のインストール（オプション）

Mermaid図を使用する場合のみ必要です。

### 前提条件
Node.js が必要です: https://nodejs.org/

### インストール
```powershell
npm install -g @mermaid-js/mermaid-cli
```

### 確認
```powershell
mmdc --version
```

---

## 6. 環境変数の設定

### PATH に追加が必要なディレクトリ

```
C:\Users\<username>\AppData\Local\Pandoc\          # Pandoc
C:\Users\<username>\AppData\Roaming\TinyTeX\bin\windows\  # TinyTeX
```

### PowerShellで一時的に設定
```powershell
$env:PATH = "C:\path\to\pandoc;C:\path\to\tinytex\bin\windows;$env:PATH"
```

### システム環境変数に永続的に追加
1. 「システムのプロパティ」→「環境変数」
2. PATH に上記ディレクトリを追加

---

## 7. ビルド実行

### コマンドライン
```powershell
pandoc sample_paper.md `
  -f markdown-smart `
  -o sample_paper.pdf `
  --pdf-engine=xelatex `
  --lua-filter=pandoc/mermaid.lua `
  --lua-filter=pandoc/paper-filter.lua `
  --filter=pandoc-crossref `
  --citeproc `
  --bibliography=references.bib `
  --csl=japanese-reference.csl `
  --lua-filter=pandoc/cite-superscript.lua `
  --number-sections `
  -V mainfont="Harano Aji Mincho" `
  -V geometry:top=30mm,bottom=30mm,left=20mm,right=20mm `
  --include-in-header=pandoc/header.tex
```

### VSCode タスク
VSCode で `Ctrl+Shift+B` を押すと、`.vscode/tasks.json` に定義されたビルドタスクが実行されます。

---

## トラブルシューティング

### フォントが見つからない
```
! Package fontspec Error: The font "Harano Aji Mincho" cannot be found.
```
**解決策**:
- `OSFONTDIR` 環境変数にフォントディレクトリを設定
- または `-V mainfont="Noto Sans CJK JP"` など別のフォントを指定

### pandoc-crossref のバージョン不一致
```
pandoc-crossref was compiled with pandoc X.X but is being run with Y.Y
```
**解決策**:
- Pandocのバージョンに合ったpandoc-crossrefをダウンロード

### LaTeXパッケージが見つからない
```
! LaTeX Error: File `xecjk.sty' not found.
```
**解決策**:
```powershell
tlmgr install xecjk
```

### Mermaidが動作しない
```
mmdc: command not found
```
**解決策**:
- Node.js がインストールされているか確認
- `npm install -g @mermaid-js/mermaid-cli` を再実行

---

## 参考リンク

- Pandoc公式ドキュメント: https://pandoc.org/MANUAL.html
- pandoc-crossref: https://lierdakil.github.io/pandoc-crossref/
- TinyTeX: https://yihui.org/tinytex/
- Mermaid: https://mermaid.js.org/
