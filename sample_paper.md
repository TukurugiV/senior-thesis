---
document_year: "令和7年度"
document_type: "卒業論文"
title: "光学式モーションキャプチャ補助デバイスの開発"
student_id: "15611"
author: "中野晃聖"
affiliation: "制御情報工学科"
supervisor: "内堀晃彦"
date: "令和8年1月30日"
lang: ja
indent: true
mainfont: "Harano Aji Mincho"
linestretch: 1.25
parskip: 0.5em
figPrefiz: "図"
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
    number_sections: true
    toc: false
    pandoc_args:
      - "--lua-filter=pandoc/paper-filter.lua"
      - "--filter=pandoc-crossref"
      - "--citeproc"
      - "--bibliography=references.bib"
      - "--csl=japanese-reference.csl"
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

# 緒言
## 背景

近年，モーションキャプチャ技術は，映像制作，スポーツ科学，医療・リハビリテーション，ロボティクス，ヒューマンインターフェースなど，多様な分野において広く利用されている．人体の動作を三次元空間上で計測し，骨格モデルや三次元モデルへ反映することにより，アニメーション生成や動作の定量的な評価，訓練・治療支援の高度化が可能となる．

一方，近年の動作解析では，人体の運動だけでなく，道具操作や手作業を伴う動作の理解が重要視されている．例えば，作業支援ロボットの研究，リハビリテーション動作の評価においては，人体の動きに加え，手に持つ工具や操作対象といった小型物体の運動を同時に計測することが求められる．このような小型物体を含めた動作計測は，動作全体の因果関係や操作意図を理解する上で重要な要素である[@vanani2025mesquite] [@twist]．

モーションキャプチャには複数の方式が存在するが，代表的なものとして光学式モーションキャプチャが挙げられる．光学式モーションキャプチャは，複数台のカメラによりマーカを撮影し，その三次元位置を算出することで，高精度な絶対位置および姿勢情報を取得できるという利点を有する[@OptiTrackBase] [@spiceMocapAll]．しかし，小型物体を対象とした場合，十分な数のマーカを配置することが困難であることや，手や身体による遮蔽の影響を受けやすいことから，安定した計測が困難となる．その結果，小型物体の姿勢情報が欠損しやすく，連続的な動作解析が妨げられるという課題が存在する[@spiceMocapAll]．

これに対し，慣性式モーションキャプチャは加速度センサおよびジャイロセンサを内蔵したIMUを対象に装着し，センサの情報から姿勢変化を推定する方式である．慣性式は遮蔽物の影響を受けにくく，センサを装着可能であれば連続的に姿勢変化を取得できるため，小型物体の計測に適している．一方で，角速度の時間積分による姿勢推定では誤差が蓄積しやすく，長時間計測において姿勢の信頼性が低下するという問題がある[@intertialMoCapMerit]．

光学式モーションキャプチャと慣性式モーションキャプチャを併用する研究事例[@OpticalAndInertialMoCap] [@MultiSensorHumanGaitDataset]は存在するものの，多くは人体動作の補完を主目的としたものであり，小型物体の動作計測を主目的として統合的に設計されたシステムは十分に検討されていない．

## 目的

光学式モーションキャプチャによって得られる高精度な絶対位置・姿勢情報を基準とし，慣性式モーションキャプチャによって得られる相対的な回転情報を組み合わせることで，両方式の欠点を相互に補完する統合的な計測環境を構築できれば，従来手法よりも高精度かつ安定したモーションキャプチャの実現が期待される．

本研究では，この考え方に基づき，光学式モーションキャプチャを基準とし，慣性式モーションキャプチャの手法を組み合わせた小型補助デバイスの開発を目的とする．

## 研究方針
本研究では，光学式モーションキャプチャシステムであるOptiTrackと連携可能な小型補助デバイスをnRF52840を用いて開発する．本デバイスは小型物体への装着を想定した小型・軽量構成とし，搭載したIMUから小型物体の姿勢変化を推定する．

取得された小型物体の相対的な姿勢情報を，光学式モーションキャプチャによって得られる人体の絶対位置・姿勢情報と統合することで，小型物体を含めた動作を同一座標系上で扱う計測システムを構築する．これにより，遮蔽やマーカ制約によって光学式のみでは取得が困難であった小型物体の動作情報を補完する．

## 論文の構成
本論文の構成を以下に記す．

# 