#include <bluefruit.h>
#include <Adafruit_NeoPixel.h>
#include <LSM6DS3.h>
#include <Wire.h>

#define TARGET_FPS 120
#define SEND_INTERVAL_MS (1000 / TARGET_FPS)

#define ENABLE_DEBUG true
#define ENABLE_STATS true

#define PACKET_HEADER 0xAA55

#define REQUEST_CHAR_UUID  0x5679  // リクエスト受信用Characteristic

// パケット構造体（リクエストされたシーケンス番号を含む）
struct __attribute__((packed)) IMUPacket {
  uint16_t header;      // 0xAA55 (同期マーカー)
  uint32_t seq;         // 内部シーケンス番号
  uint32_t requestSeq;  // リクエストされたシーケンス番号（Receiverからの同期シーケンス）
  int16_t gx;           // ジャイロX軸 (生データ: -32768 ~ 32767)
  int16_t gy;           // ジャイロY軸 (生データ)
  int16_t gz;           // ジャイロZ軸 (生データ)
  int16_t ax;           // 加速度X軸 (生データ: -32768 ~ 32767)
  int16_t ay;           // 加速度Y軸 (生データ)
  int16_t az;           // 加速度Z軸 (生データ)
  uint16_t checksum;    // 簡易チェックサム
};

LSM6DS3 imu(I2C_MODE, 0x6A);

#ifndef PIN_NEOPIXEL
  #define PIN_NEOPIXEL  11
#endif

Adafruit_NeoPixel pixel(1, PIN_NEOPIXEL, NEO_GRB + NEO_KHZ800);

BLEService        customService(0x1234);
BLECharacteristic txChar(0x5678);
BLECharacteristic requestChar(REQUEST_CHAR_UUID);  // リクエスト受信用

void cccd_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint16_t cccd_value);
void request_write_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint8_t* data, uint16_t len);

void startAdv();

// リクエストされたシーケンス番号
volatile uint32_t requestedSequence = 0;
volatile bool hasNewRequest = false;

enum LedMode {
  LEDMODE_ADV,
  LEDMODE_CONNECTED,
  LEDMODE_CCCD_PULSE,
  LEDMODE_NOTIFY_ERROR,
  LEDMODE_REQUEST_RECEIVED
};

LedMode  ledMode       = LEDMODE_ADV;
uint32_t ledModeExpire = 0;
bool     ledState      = false;
uint32_t ledBlinkPrev  = 0;

void setPixelColor(uint8_t r, uint8_t g, uint8_t b) {
  pixel.setPixelColor(0, pixel.Color(r, g, b));
  pixel.show();
}

void showColor(bool on, uint8_t r, uint8_t g, uint8_t b) {
  if (on) {
    setPixelColor(r, g, b);
  } else {
    setPixelColor(0, 0, 0);
  }
}

void updateLed() {
  static uint32_t lastUpdate = 0;
  uint32_t now = millis();

  if (now - lastUpdate < 10) return;
  lastUpdate = now;

  if (ledMode == LEDMODE_CCCD_PULSE || ledMode == LEDMODE_NOTIFY_ERROR || ledMode == LEDMODE_REQUEST_RECEIVED) {
    if (now > ledModeExpire) {
      if (Bluefruit.connected()) {
        ledMode = LEDMODE_CONNECTED;
      } else {
        ledMode = LEDMODE_ADV;
      }
      ledState = false;
      setPixelColor(0, 0, 0);
    }
  }

  switch (ledMode) {
    case LEDMODE_ADV: {
      const uint32_t interval = 500;
      if (now - ledBlinkPrev >= interval) {
        ledBlinkPrev = now;
        ledState = !ledState;
      }
      showColor(ledState, 0, 0, 255);
    } break;

    case LEDMODE_CONNECTED: {
      ledState = true;
      showColor(true, 0, 255, 0);
    } break;

    case LEDMODE_CCCD_PULSE: {
      ledState = true;
      showColor(true, 255, 255, 0);
    } break;

    case LEDMODE_NOTIFY_ERROR: {
      const uint32_t interval = 100;
      if (now - ledBlinkPrev >= interval) {
        ledBlinkPrev = now;
        ledState = !ledState;
      }
      showColor(ledState, 255, 0, 0);
    } break;

    case LEDMODE_REQUEST_RECEIVED: {
      ledState = true;
      showColor(true, 0, 255, 255);  // シアン: リクエスト受信
    } break;
  }
}

void setup() {
  Serial.begin(115200);
  #if ENABLE_DEBUG
  // タイムアウト付きでシリアル接続を待つ（最大1秒）
  for (int i = 0; i < 100 && !Serial; i++) {
    delay(10);
  }
  #else
  delay(100);
  #endif

  #if ENABLE_DEBUG
  Serial.println("=== XIAO Peripheral (TX) - 120Hz Gyro BLE Sender with Sync ===");
  Serial.print("Target FPS: ");
  Serial.println(TARGET_FPS);
  Serial.print("Send interval: ");
  Serial.print(SEND_INTERVAL_MS);
  Serial.println(" ms");
  Serial.print("IMUPacket size: ");
  Serial.print(sizeof(IMUPacket));
  Serial.println(" bytes");
  #endif

  // I2C初期化
  Wire.begin();
  Wire.setClock(400000);
  delay(100);

  // IMU センサー初期化
  imu.settings.gyroRange = 2000;
  imu.settings.accelRange = 4;

  #if ENABLE_DEBUG
  Serial.println("Initializing IMU sensor...");
  #endif

  uint16_t result = imu.begin();
  if (result != 0) {
    #if ENABLE_DEBUG
    Serial.print("IMU initialization failed! Error code: ");
    Serial.println(result);

    Serial.println("Scanning I2C bus...");
    for (uint8_t addr = 1; addr < 127; addr++) {
      Wire.beginTransmission(addr);
      if (Wire.endTransmission() == 0) {
        Serial.print("Found I2C device at 0x");
        if (addr < 16) Serial.print("0");
        Serial.println(addr, HEX);
      }
    }
    #endif

    while (1) {
      delay(100);
    }
  }

  // IMU SETTINGS
  imu.writeRegister(LSM6DS3_ACC_GYRO_CTRL2_G,  0x8C);
  imu.writeRegister(LSM6DS3_ACC_GYRO_CTRL1_XL, 0x8A);
  imu.writeRegister(LSM6DS3_ACC_GYRO_CTRL7_G,  0x00);
  imu.writeRegister(LSM6DS3_ACC_GYRO_CTRL8_XL, 0x09);

  #if ENABLE_DEBUG
  Serial.println("IMU initialized successfully!");
  #endif

  pixel.begin();
  pixel.setBrightness(32);
  setPixelColor(0, 0, 0);
  ledMode      = LEDMODE_ADV;
  ledBlinkPrev = millis();

  Bluefruit.begin();
  Bluefruit.setName("XIAO_TX_120Hz");

  Bluefruit.Periph.setConnInterval(6, 6);
  Bluefruit.Periph.setConnSupervisionTimeout(400);

  Bluefruit.Periph.setConnectCallback([](uint16_t conn_hdl) {
    #if ENABLE_DEBUG
    Serial.println("Central connected");

    uint16_t mtu = Bluefruit.Connection(conn_hdl)->getMtu();
    Serial.print("Negotiated MTU: ");
    Serial.println(mtu);
    #endif

    ledMode = LEDMODE_CONNECTED;
  });

  Bluefruit.Periph.setDisconnectCallback([](uint16_t conn_hdl, uint8_t reason) {
    #if ENABLE_DEBUG
    Serial.print("Central disconnected, reason = ");
    Serial.println(reason);
    #endif
    ledMode = LEDMODE_ADV;
    // リクエストシーケンスをリセット
    requestedSequence = 0;
    hasNewRequest = false;
  });

  customService.begin();

  // データ送信用Characteristic (Notify)
  txChar.setProperties(CHR_PROPS_NOTIFY);
  txChar.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  txChar.setMaxLen(sizeof(IMUPacket));
  txChar.setCccdWriteCallback(cccd_callback);
  txChar.begin();

  // リクエスト受信用Characteristic (Write)
  requestChar.setProperties(CHR_PROPS_WRITE | CHR_PROPS_WRITE_WO_RESP);
  requestChar.setPermission(SECMODE_OPEN, SECMODE_OPEN);
  requestChar.setMaxLen(sizeof(uint32_t));
  requestChar.setWriteCallback(request_write_callback);
  requestChar.begin();

  startAdv();

  #if ENABLE_DEBUG
  Serial.println("Setup complete. Ready to send gyro data at 120Hz via BLE.");
  Serial.println("Waiting for sequence requests from Central...");
  #endif
}

void loop() {
  static uint32_t counter = 0;
  static uint32_t lastLogTime = 0;
  static uint32_t sentCount = 0;
  static uint32_t failCount = 0;

  uint32_t now = millis();

  // リクエストベース送信: リクエストを受け取った時だけデータを送信
  if (Bluefruit.connected() && hasNewRequest) {
    hasNewRequest = false;  // フラグをクリア

    // IMU DATA READ
    float gyroX_f = imu.readFloatGyroX();
    float gyroY_f = imu.readFloatGyroY();
    float gyroZ_f = imu.readFloatGyroZ();

    float accelX_f = imu.readFloatAccelX();
    float accelY_f = imu.readFloatAccelY();
    float accelZ_f = imu.readFloatAccelZ();

    int16_t gyroX = constrain((int16_t)(gyroX_f * 16.384), -32768, 32767);
    int16_t gyroY = constrain((int16_t)(gyroY_f * 16.384), -32768, 32767);
    int16_t gyroZ = constrain((int16_t)(gyroZ_f * 16.384), -32768, 32767);

    int16_t accelX = constrain((int16_t)(accelX_f * 8192), -32768, 32767);
    int16_t accelY = constrain((int16_t)(accelY_f * 8192), -32768, 32767);
    int16_t accelZ = constrain((int16_t)(accelZ_f * 8192), -32768, 32767);

    // 現在のリクエストシーケンスを取得
    uint32_t currentRequestSeq = requestedSequence;

    IMUPacket packet;
    packet.header = PACKET_HEADER;
    packet.seq = counter;
    packet.requestSeq = currentRequestSeq;  // リクエストされたシーケンス番号を含める
    packet.gx = gyroX;
    packet.gy = gyroY;
    packet.gz = gyroZ;
    packet.ax = accelX;
    packet.ay = accelY;
    packet.az = accelZ;

    // チェックサムを計算（requestSeqも含める）
    packet.checksum = packet.header ^ (packet.seq & 0xFFFF) ^ ((packet.seq >> 16) & 0xFFFF)
                    ^ (packet.requestSeq & 0xFFFF) ^ ((packet.requestSeq >> 16) & 0xFFFF)
                    ^ packet.gx ^ packet.gy ^ packet.gz
                    ^ packet.ax ^ packet.ay ^ packet.az;

    bool ok = txChar.notify((uint8_t*)&packet, sizeof(packet));

    if (!ok) {
      failCount++;
      ledMode       = LEDMODE_NOTIFY_ERROR;
      ledModeExpire = millis() + 1000;
      ledBlinkPrev  = millis();
      
      #if ENABLE_DEBUG
      Serial.println("Failed to send data packet");
      #endif
    } else {
      sentCount++;
      counter++;
      
      #if ENABLE_DEBUG
      Serial.print("Sent packet #");
      Serial.print(counter - 1);
      Serial.print(" for request seq: ");
      Serial.println(currentRequestSeq);
      #endif
    }
  }

  #if ENABLE_STATS
  if (now - lastLogTime >= 1000) {
    lastLogTime = now;
    if (Bluefruit.connected()) {
      Serial.print("Sent: ");
      Serial.print(sentCount);
      Serial.print(" pkts/s | Failed: ");
      Serial.print(failCount);
      Serial.print(" | Total: ");
      Serial.print(counter);
      Serial.print(" | ReqSeq: ");
      Serial.println(requestedSequence);
    }
    sentCount = 0;
    failCount = 0;
  }
  #endif

  updateLed();
}

// リクエスト受信コールバック
void request_write_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint8_t* data, uint16_t len) {
  (void)conn_hdl;
  (void)chr;

  if (len >= sizeof(uint32_t)) {
    uint32_t newSeq;
    memcpy(&newSeq, data, sizeof(uint32_t));
    requestedSequence = newSeq;
    hasNewRequest = true;

    #if ENABLE_DEBUG
    Serial.print("Received sequence request: ");
    Serial.println(newSeq);
    #endif

    // LED表示
    ledMode = LEDMODE_REQUEST_RECEIVED;
    ledModeExpire = millis() + 100;
  }
}

void cccd_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint16_t cccd_value) {
  #if ENABLE_DEBUG
  Serial.print("CCCD updated: conn=");
  Serial.print(conn_hdl);
  Serial.print(" value=0x");
  Serial.println(cccd_value, HEX);
  #endif

  ledMode       = LEDMODE_CCCD_PULSE;
  ledModeExpire = millis() + 200;
}

void startAdv() {
  Bluefruit.Advertising.stop();

  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(customService);
  Bluefruit.Advertising.addName();

  Bluefruit.Advertising.restartOnDisconnect(true);

  Bluefruit.Advertising.setInterval(32, 244);
  Bluefruit.Advertising.setFastTimeout(30);
  Bluefruit.Advertising.start(0);

  #if ENABLE_DEBUG
  Serial.println("Advertising started - Device name: XIAO_TX_120Hz");
  #endif

  ledMode      = LEDMODE_ADV;
  ledBlinkPrev = millis();
}
