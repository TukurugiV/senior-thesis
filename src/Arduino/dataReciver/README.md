# dataReciver.ino

BLE Central デバイスとして動作し、IMUセンサーデバイス（dataSender）からデータを受信するプログラム。

## 概要

XIAO nRF52840 マイコンボードで動作するBluetooth Low Energy (BLE) Central プログラム。BLE Peripheral（dataSender）と接続してIMUセンサーデータを受信し、シリアルポート経由でPCに転送する。

## ハードウェア要件

- **マイコンボード**: Seeed XIAO nRF52840
- **ライブラリ**: Adafruit Bluefruit nRF52 Library

## ピン配置

| ピン | 機能 | 説明 |
|------|------|------|
| GPIO6 | SYNC_RESET_PIN | シーケンス番号リセット（立ち上がりエッジ） |
| GPIO7 | SYNC_COUNT_PIN | シーケンス番号カウントアップ（立ち上がりエッジ） |

## 設定パラメータ

```cpp
#define ENABLE_DEBUG true           // デバッグ出力有効/無効
#define AUTO_REQUEST_MODE true      // 自動リクエストモード
#define AUTO_REQUEST_INTERVAL 100   // 自動リクエスト間隔 (ms)
```

## 動作モード

### 1. 自動リクエストモード (`AUTO_REQUEST_MODE = true`)

- 外部パルス入力なしで動作
- 100ms間隔で自動的にシーケンス番号をインクリメント
- デバッグ用途や単独テストに適している

### 2. パルスモード (`AUTO_REQUEST_MODE = false`)

- GPIO入力によるシーケンス管理
- GPIO7の立ち上がりエッジでシーケンス番号がカウントアップ
- GPIO6の立ち上がりエッジでシーケンス番号が0にリセット
- 外部装置との同期が必要な場合に使用

## BLE仕様

### UUID定義

| 項目 | UUID |
|------|------|
| データサービス | 0x1234 |
| データCharacteristic | 0x5678 |
| リクエストCharacteristic | 0x5679 |

### 通信パラメータ

- **MTU**: 50バイト（交換要求）
- **接続間隔**: 6（最小接続間隔）
- **スキャン間隔**: 160 (100ms)
- **スキャンウィンドウ**: 80 (50ms)

## パケット仕様

受信パケットサイズ: **24バイト**

| オフセット | サイズ | 内容 |
|------------|--------|------|
| 0-1 | 2 | ヘッダ (0x55, 0xAA) |
| 2-5 | 4 | シーケンス番号 |
| 6-9 | 4 | リクエストシーケンス番号 |
| 10-11 | 2 | ジャイロX (int16) |
| 12-13 | 2 | ジャイロY (int16) |
| 14-15 | 2 | ジャイロZ (int16) |
| 16-17 | 2 | 加速度X (int16) |
| 18-19 | 2 | 加速度Y (int16) |
| 20-21 | 2 | 加速度Z (int16) |
| 22-23 | 2 | チェックサム |

## 主要関数

### `setup()`
初期化処理を行う。
- シリアル通信初期化（921600 bps）
- GPIO入力・割り込み設定
- BLEライブラリ初期化
- スキャン開始

### `loop()`
メインループ。動作モードに応じた処理を実行。
- 自動リクエストモード: 定期的にシーケンスをインクリメントしてリクエスト送信
- パルスモード: 割り込みフラグを監視してリクエスト送信

### `sendSequenceRequest()`
BLE Peripheral に対してシーケンス番号付きのリクエストを送信。

```cpp
void sendSequenceRequest() {
    uint32_t seq = currentSequence;
    requestChar.write32(seq);
}
```

### `scan_callback()`
BLEスキャン時のコールバック。デバイス発見時に自動接続を試行。

### `connect_callback()`
BLE接続成功時のコールバック。
- データサービス・Characteristic の検出
- MTU交換要求
- 接続パラメータ設定
- Notification有効化

### `data_notify_callback()`
BLE Notification 受信時のコールバック。
- 24バイトパケットをバッファリング
- 完全なパケット受信時にシリアル出力

### 割り込みハンドラ

```cpp
// GPIO6: シーケンスリセット
void syncResetISR() {
    currentSequence = 0;
    syncResetTriggered = true;
}

// GPIO7: シーケンスカウントアップ
void syncCountISR() {
    currentSequence++;
    syncCountTriggered = true;
}
```

## データフロー

```
┌─────────────────────────────────┐
│  dataSender (BLE Peripheral)   │
│  IMUセンサーデバイス            │
└──────────────┬──────────────────┘
               │ BLE Notification
               ↓
┌─────────────────────────────────┐
│  dataReciver (BLE Central)     │
│  ・BLE接続管理                  │
│  ・パケット受信・バッファリング  │
│  ・シーケンス管理                │
└──────────────┬──────────────────┘
               │ シリアル出力 (921600 bps)
               ↓
┌─────────────────────────────────┐
│  PC (main.rs)                  │
│  姿勢計算プログラム             │
└─────────────────────────────────┘
```

## シリアル出力

- **ボーレート**: 921600 bps
- **出力形式**: バイナリ（24バイトパケットをそのまま出力）

## 注意事項

1. `ENABLE_DEBUG` を `false` にすると、デバッグメッセージが出力されなくなり、通信効率が向上する
2. パルスモード使用時は、GPIO6/7 に適切なプルアップ抵抗が必要
3. BLE接続が切断された場合、自動的にスキャンを再開する
