# dataSender.ino

BLE Peripheral デバイスとして動作し、IMUセンサーデータを送信するプログラム。

## 概要

XIAO nRF52840 マイコンボードで動作するBluetooth Low Energy (BLE) Peripheral プログラム。内蔵の LSM6DS3 IMUセンサーからジャイロスコープと加速度データを読み取り、BLE Central（dataReciver）からのリクエストに応じてデータを送信する。

## ハードウェア要件

- **マイコンボード**: Seeed XIAO nRF52840 Sense（IMU内蔵）
- **IMUセンサー**: LSM6DS3（I2C接続、アドレス: 0x6A）
- **LED**: NeoPixel（状態表示用）

### ライブラリ依存

- Adafruit Bluefruit nRF52 Library
- Adafruit NeoPixel Library
- LSM6DS3 Library

## 設定パラメータ

```cpp
#define TARGET_FPS 120              // 目標フレームレート
#define SEND_INTERVAL_MS 8          // 送信間隔 (1000/120 ≒ 8ms)
#define ENABLE_DEBUG true           // デバッグ出力有効/無効
#define ENABLE_STATS true           // 統計情報出力有効/無効
```

## IMUセンサー設定

| パラメータ | 設定値 | 説明 |
|------------|--------|------|
| ジャイロレンジ | ±2000 dps | 角速度測定範囲 |
| 加速度レンジ | ±4 g | 加速度測定範囲 |
| I2Cクロック | 400 kHz | 高速モード |

### レジスタ設定

```cpp
// CTRL2_G: ジャイロ設定 (1.66kHz, 2000dps)
imu.writeRegister(LSM6DS3_ACC_GYRO_CTRL2_G,  0x8C);

// CTRL1_XL: 加速度設定 (1.66kHz, 4g)
imu.writeRegister(LSM6DS3_ACC_GYRO_CTRL1_XL, 0x8A);

// CTRL7_G: ジャイロフィルタ設定
imu.writeRegister(LSM6DS3_ACC_GYRO_CTRL7_G,  0x00);

// CTRL8_XL: 加速度フィルタ設定
imu.writeRegister(LSM6DS3_ACC_GYRO_CTRL8_XL, 0x09);
```

## BLE仕様

### UUID定義

| 項目 | UUID |
|------|------|
| カスタムサービス | 0x1234 |
| データ送信Characteristic | 0x5678 |
| リクエスト受信Characteristic | 0x5679 |

### Characteristic設定

**データ送信 (txChar)**
- プロパティ: Notify
- パーミッション: 読み取り可、書き込み不可
- 最大長: 24バイト

**リクエスト受信 (requestChar)**
- プロパティ: Write, Write Without Response
- パーミッション: 読み書き可
- 最大長: 4バイト（uint32_t）

### アドバタイジング設定

| パラメータ | 設定値 |
|------------|--------|
| 間隔（最小） | 32 (20ms) |
| 間隔（最大） | 244 (152.5ms) |
| 高速タイムアウト | 30秒 |
| デバイス名 | XIAO_TX_120Hz |

## パケット仕様

### IMUPacket構造体（24バイト）

```cpp
struct __attribute__((packed)) IMUPacket {
    uint16_t header;      // 0xAA55 (同期マーカー)
    uint32_t seq;         // 内部シーケンス番号
    uint32_t requestSeq;  // リクエストシーケンス番号
    int16_t gx;           // ジャイロX軸
    int16_t gy;           // ジャイロY軸
    int16_t gz;           // ジャイロZ軸
    int16_t ax;           // 加速度X軸
    int16_t ay;           // 加速度Y軸
    int16_t az;           // 加速度Z軸
    uint16_t checksum;    // チェックサム
};
```

### データスケーリング

| センサー | 変換係数 | 計算式 |
|----------|----------|--------|
| ジャイロ | 16.384 LSB/dps | `(int16_t)(float_dps * 16.384)` |
| 加速度 | 8192 LSB/g | `(int16_t)(float_g * 8192)` |

### チェックサム計算

```cpp
checksum = header ^ (seq & 0xFFFF) ^ ((seq >> 16) & 0xFFFF)
         ^ (requestSeq & 0xFFFF) ^ ((requestSeq >> 16) & 0xFFFF)
         ^ gx ^ gy ^ gz ^ ax ^ ay ^ az;
```

## LED状態表示

| モード | 色 | 動作 | 意味 |
|--------|----|----|------|
| LEDMODE_ADV | 青 | 点滅 (500ms) | アドバタイジング中 |
| LEDMODE_CONNECTED | 緑 | 点灯 | BLE接続中 |
| LEDMODE_CCCD_PULSE | 黄 | 点灯 (200ms) | CCCD更新 |
| LEDMODE_NOTIFY_ERROR | 赤 | 高速点滅 (100ms) | 送信エラー |
| LEDMODE_REQUEST_RECEIVED | シアン | 点灯 (100ms) | リクエスト受信 |

## 主要関数

### `setup()`
初期化処理を行う。
- シリアル通信初期化（115200 bps）
- I2C初期化（400kHz）
- IMUセンサー初期化・設定
- NeoPixel初期化
- BLEライブラリ初期化
- サービス・Characteristic設定
- アドバタイジング開始

### `loop()`
メインループ。
- リクエスト受信時にIMUデータを読み取り送信
- 統計情報の定期出力（1秒ごと）
- LED状態更新

### `request_write_callback()`
BLE Central からのリクエスト受信コールバック。

```cpp
void request_write_callback(uint16_t conn_hdl, BLECharacteristic* chr,
                            uint8_t* data, uint16_t len) {
    if (len >= sizeof(uint32_t)) {
        uint32_t newSeq;
        memcpy(&newSeq, data, sizeof(uint32_t));
        requestedSequence = newSeq;
        hasNewRequest = true;
    }
}
```

### `cccd_callback()`
CCCD（Client Characteristic Configuration Descriptor）更新時のコールバック。Notification の有効/無効が切り替わった際に呼ばれる。

### `startAdv()`
BLEアドバタイジングを開始。
- フラグ設定
- TX Power追加
- サービスUUID追加
- デバイス名追加

### `updateLed()`
LED状態を更新。現在のモードに応じて色と点滅パターンを制御。

## リクエストベース送信方式

このプログラムは**リクエストベース**の送信方式を採用している。

1. BLE Central（dataReciver）がシーケンス番号付きのリクエストを送信
2. dataSender がリクエストを受信すると `hasNewRequest` フラグが立つ
3. `loop()` 内でフラグを検出し、IMUデータを読み取って送信
4. 送信パケットには受信したリクエストシーケンス番号が含まれる

この方式により、Central側のタイミングに同期したデータ収集が可能。

## データフロー

```
┌─────────────────────────────────┐
│  LSM6DS3 IMUセンサー            │
│  ジャイロ・加速度               │
└──────────────┬──────────────────┘
               │ I2C (400kHz)
               ↓
┌─────────────────────────────────┐
│  dataSender (BLE Peripheral)   │
│  ・IMUデータ読み取り            │
│  ・パケット生成                 │
│  ・BLE Notification送信         │
└──────────────┬──────────────────┘
               │ BLE Notification
               ↓
┌─────────────────────────────────┐
│  dataReciver (BLE Central)     │
│  データ受信デバイス             │
└─────────────────────────────────┘
```

## シリアル出力

- **ボーレート**: 115200 bps
- **デバッグモード時の出力例**:
  ```
  === XIAO Peripheral (TX) - 120Hz Gyro BLE Sender with Sync ===
  Target FPS: 120
  Send interval: 8 ms
  IMUPacket size: 24 bytes
  Sent: 95 pkts/s | Failed: 0 | Total: 1234 | ReqSeq: 567
  ```

## 注意事項

1. IMUセンサーの初期化に失敗した場合、プログラムは無限ループで停止する
2. `ENABLE_DEBUG` を `false` にすると、シリアル出力が最小限になり処理効率が向上
3. BLE接続が切断された場合、リクエストシーケンスは0にリセットされる
4. Notification送信に失敗した場合、赤LEDが高速点滅して警告を表示
