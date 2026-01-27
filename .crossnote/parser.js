/**
 * Markdown Preview Enhanced カスタムパーサー
 * 論文向けの図表番号自動採番と参照機能
 */

// フロントマターを保持するグローバル変数
let _frontmatter = {};

({
  onWillParseMarkdown: async function (markdown) {

    // フロントマターを解析
    _frontmatter = {};
    const fmMatch = markdown.match(/^---\n([\s\S]*?)\n---/);
    if (fmMatch) {
      const fmContent = fmMatch[1];
      // 簡易YAMLパース
      fmContent.split('\n').forEach(line => {
        const match = line.match(/^(\w+):\s*"?([^"]*)"?$/);
        if (match) {
          _frontmatter[match[1]] = match[2];
        }
      });
    }

    // コードブロックを保護（処理対象から除外）
    const codeBlocks = [];
    markdown = markdown.replace(/```[\s\S]*?```/g, (match) => {
      codeBlocks.push(match);
      return `___CODE_BLOCK_${codeBlocks.length - 1}___`;
    });

    // 図表カウンター
    let figureCount = 0;
    let tableCount = 0;
    let equationCount = 0;

    // 図表マップ（ラベル → 番号）
    const figureMap = {};
    const tableMap = {};
    const equationMap = {};

    // ステップ1: すべての図をスキャンして番号を割り当て
    markdown = markdown.replace(
      /!\[([^\]]*)\]\(([^)]+)\)\{#fig:([a-zA-Z0-9_-]+)\}/g,
      (match, caption, src, label) => {
        figureCount++;
        figureMap[label] = figureCount;
        return `<div class="figure" id="fig:${label}">
<img src="${src}" alt="${caption}">
<p class="caption"><span class="figure-number">図 ${figureCount}:</span> ${caption}</p>
</div>`;
      }
    );

    // ステップ2: すべての表をスキャンして番号を割り当て
    // [キャプション]{#tbl:label} の後に空行があってもなくても対応
    markdown = markdown.replace(
      /\[([^\]]+)\]\{#tbl:([a-zA-Z0-9_-]+)\}\n\n?((?:\|[^\n]+\n?)+)/g,
      (match, caption, label, tableContent) => {
        tableCount++;
        tableMap[label] = tableCount;

        // MarkdownテーブルをHTMLに変換
        const rows = tableContent.trim().split('\n');
        let tableHtml = '<table>\n';

        rows.forEach((row, index) => {
          // 区切り行（|---|---|）をスキップ
          if (/^\|[\s-:|]+\|$/.test(row)) return;

          const cells = row.split('|').filter((cell, i, arr) => i > 0 && i < arr.length - 1);
          const tag = index === 0 ? 'th' : 'td';
          const rowTag = index === 0 ? 'thead' : (index === 1 ? 'tbody' : '');

          if (rowTag === 'thead') tableHtml += '<thead>\n';
          if (rowTag === 'tbody') tableHtml += '<tbody>\n';

          tableHtml += '<tr>';
          cells.forEach(cell => {
            tableHtml += `<${tag}>${cell.trim()}</${tag}>`;
          });
          tableHtml += '</tr>\n';

          if (index === 0) tableHtml += '</thead>\n';
        });

        tableHtml += '</tbody>\n</table>';

        return `<div class="table-wrapper" id="tbl:${label}">
<p class="table-caption"><span class="table-number">表 ${tableCount}:</span> ${caption}</p>
${tableHtml}
</div>`;
      }
    );

    // ステップ3: すべての数式をスキャンして番号を割り当て
    markdown = markdown.replace(
      /\$\$([^$]+)\$\$\{#eq:([a-zA-Z0-9_-]+)\}/g,
      (match, equation, label) => {
        equationCount++;
        equationMap[label] = equationCount;
        return `<div class="equation" id="eq:${label}">

$$${equation}$$

<span class="equation-number">(${equationCount})</span>
</div>`;
      }
    );

    // ステップ4: 参照を解決
    // 図の参照
    markdown = markdown.replace(
      /\[@fig:([a-zA-Z0-9_-]+)\]/g,
      (match, label) => {
        const num = figureMap[label];
        return num ? `[図 ${num}](#fig:${label})` : match;
      }
    );

    // 表の参照
    markdown = markdown.replace(
      /\[@tbl:([a-zA-Z0-9_-]+)\]/g,
      (match, label) => {
        const num = tableMap[label];
        return num ? `[表 ${num}](#tbl:${label})` : match;
      }
    );

    // 数式の参照
    markdown = markdown.replace(
      /\[@eq:([a-zA-Z0-9_-]+)\]/g,
      (match, label) => {
        const num = equationMap[label];
        return num ? `[(${num})](#eq:${label})` : match;
      }
    );

    // ステップ5: カスタム環境の処理
    // 定理環境
    markdown = markdown.replace(/:::theorem\s+([^\n]*)\n([\s\S]*?)\n:::/g, (match, title, content) => {
      let result = '<div class="theorem">\n\n**定理:** ' + title + '\n\n' + content + '\n\n</div>';
      return result;
    });

    // 証明環境
    markdown = markdown.replace(/:::proof\n([\s\S]*?)\n:::/g, (match, content) => {
      let result = '<div class="proof">\n\n**証明:**\n\n' + content + '\n\n<div class="qed">□</div>\n\n</div>';
      return result;
    });

    // 補題環境
    markdown = markdown.replace(/:::lemma\s+([^\n]*)\n([\s\S]*?)\n:::/g, (match, title, content) => {
      let result = '<div class="lemma">\n\n**補題:** ' + title + '\n\n' + content + '\n\n</div>';
      return result;
    });

    // 定義環境
    markdown = markdown.replace(/:::definition\s+([^\n]*)\n([\s\S]*?)\n:::/g, (match, title, content) => {
      let result = '<div class="definition">\n\n**定義:** ' + title + '\n\n' + content + '\n\n</div>';
      return result;
    });

    // 例環境
    markdown = markdown.replace(/:::example\s+([^\n]*)\n([\s\S]*?)\n:::/g, (match, title, content) => {
      let result = '<div class="example">\n\n**例:** ' + title + '\n\n' + content + '\n\n</div>';
      return result;
    });

    // 注釈環境（note）
    markdown = markdown.replace(/:::note\n([\s\S]*?)\n:::/g, (match, content) => {
      let result = '<div class="note">\n\n📝 **注:**\n\n' + content + '\n\n</div>';
      return result;
    });

    // アルゴリズム環境（追加機能）
    markdown = markdown.replace(/:::algorithm\s+([^\n]*)\n([\s\S]*?)\n:::/g, (match, title, content) => {
      let result = '<div class="algorithm">\n\n**アルゴリズム:** ' + title + '\n\n' + content + '\n\n</div>';
      return result;
    });

    // 警告環境（追加機能）
    markdown = markdown.replace(/:::warning\n([\s\S]*?)\n:::/g, (match, content) => {
      let result = '<div class="warning">\n\n⚠️ **警告:**\n\n' + content + '\n\n</div>';
      return result;
    });

    // 表紙環境（:::cover）
    markdown = markdown.replace(/:::cover\n?:::/g, () => {
      return '<div class="cover"></div>';
    });

    // コードブロックを復元
    markdown = markdown.replace(/___CODE_BLOCK_(\d+)___/g, (match, index) => {
      return codeBlocks[parseInt(index)];
    });

    return markdown;
  },

  onDidParseMarkdown: async function (html) {
    // 表紙コンテナの処理（HTML変換後）
    html = html.replace(/<div class="cover">\s*<\/div>/g, () => {
      const title = _frontmatter.title || '';
      const author = _frontmatter.author || '';
      const affiliation = _frontmatter.affiliation || '';
      const date = _frontmatter.date || '';
      return `<div class="title-page">
<h1>${title}</h1>
<div class="author">${author}</div>
<div class="affiliation">${affiliation}</div>
<div class="date">${date}</div>
</div>`;
    });
    return html;
  },
})
