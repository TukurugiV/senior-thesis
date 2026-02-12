# Dockerfile - 卒業論文ビルド環境
# Pandoc + XeLaTeX + pandoc-crossref による日本語PDF生成環境

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# ============================================================
# 1. 基本ツールのインストール
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    fontconfig \
    git \
    make \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 2. Pandoc のインストール
# ============================================================
ARG PANDOC_VERSION=3.6.4
RUN curl -fsSL "https://github.com/jgm/pandoc/releases/download/${PANDOC_VERSION}/pandoc-${PANDOC_VERSION}-1-amd64.deb" \
    -o /tmp/pandoc.deb \
    && dpkg -i /tmp/pandoc.deb \
    && rm /tmp/pandoc.deb

# ============================================================
# 3. pandoc-crossref のインストール
# ============================================================
ARG CROSSREF_VERSION=0.3.18.1
RUN curl -fsSL "https://github.com/lierdakil/pandoc-crossref/releases/download/v${CROSSREF_VERSION}/pandoc-crossref-Linux-X64.tar.xz" \
    -o /tmp/pandoc-crossref.tar.xz \
    && tar -xf /tmp/pandoc-crossref.tar.xz -C /usr/local/bin/ \
    && chmod +x /usr/local/bin/pandoc-crossref \
    && rm /tmp/pandoc-crossref.tar.xz

# ============================================================
# 4. TeX Live のインストール (XeLaTeX + 日本語サポート)
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    texlive-xetex \
    texlive-luatex \
    texlive-lang-japanese \
    texlive-latex-extra \
    texlive-latex-recommended \
    texlive-fonts-recommended \
    texlive-fonts-extra \
    texlive-science \
    texlive-plain-generic \
    latexmk \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 5. 日本語フォントのインストール
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    fonts-haranoaji \
    fonts-haranoaji-extra \
    fonts-bizud-gothic \
    fonts-bizud-mincho \
    fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/* \
    && fc-cache -fv

# ============================================================
# 6. Node.js + mermaid-cli (オプション: Mermaid図の描画用)
# ============================================================
ARG INSTALL_MERMAID=false
RUN if [ "$INSTALL_MERMAID" = "true" ]; then \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @mermaid-js/mermaid-cli \
    && rm -rf /var/lib/apt/lists/*; \
    fi

# ============================================================
# 7. 作業ディレクトリの設定
# ============================================================
WORKDIR /workspace

COPY . /workspace/

RUN chmod +x /workspace/build.sh 2>/dev/null || true

# ============================================================
# デフォルトコマンド
# ============================================================
CMD ["bash"]
