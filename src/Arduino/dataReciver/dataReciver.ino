#include <bluefruit.h>
void data_notify_callback(BLEClientCharacteristic* chr, uint8_t* data, uint16_t len);

#define DATA_SERVICE_UUID      0x1234
#define DATA_CHAR_UUID         0x5678
#define REQUEST_CHAR_UUID      0x5679  // リクエスト用Characteristic

#define ENABLE_DEBUG true

// 動作モード設定
#define AUTO_REQUEST_MODE true    // true: パルス入力なしで自動リクエスト, false: パルス入力必須
#define AUTO_REQUEST_INTERVAL 100 // 自動リクエスト間隔 (ms)

// GPIO設定
#define SYNC_RESET_PIN  6   // GPIO6: このパルスでシーケンスを0にリセット
#define SYNC_COUNT_PIN  7   // GPIO7: このパルスでシーケンスをカウントアップ

BLEClientService        dataService(DATA_SERVICE_UUID);
BLEClientCharacteristic dataChar(DATA_CHAR_UUID);
BLEClientCharacteristic requestChar(REQUEST_CHAR_UUID);  // リクエスト送信用

void scan_callback(ble_gap_evt_adv_report_t* report);
void connect_callback(uint16_t conn_handle);
void disconnect_callback(uint16_t conn_handle, uint8_t reason);

// シーケンス管理
volatile uint32_t currentSequence = 0;
volatile bool syncResetTriggered = false;
volatile bool syncCountTriggered = false;

// 割り込みハンドラ: GPIO6 - シーケンスリセット
void syncResetISR() {
  currentSequence = 0;
  syncResetTriggered = true;
}

// 割り込みハンドラ: GPIO7 - シーケンスカウントアップ
void syncCountISR() {
  currentSequence++;
  syncCountTriggered = true;
}

void setup()
{
  Serial.begin(921600);
  #if ENABLE_DEBUG
  // タイムアウト付きでシリアル接続を待つ（最大1秒）
  for (int i = 0; i < 100 && !Serial; i++) {
    delay(10);
  }
  Serial.println("=== XIAO nRF52840 Central (data receiver with sync) ===");
  Serial.println("ENABLE_DEBUG is ON");
  #else
  delay(100);
  #endif

  // GPIO設定
  pinMode(SYNC_RESET_PIN, INPUT_PULLUP);
  pinMode(SYNC_COUNT_PIN, INPUT_PULLUP);

  // 割り込み設定（立ち上がりエッジで検出）
  attachInterrupt(digitalPinToInterrupt(SYNC_RESET_PIN), syncResetISR, RISING);
  attachInterrupt(digitalPinToInterrupt(SYNC_COUNT_PIN), syncCountISR, RISING);

  #if ENABLE_DEBUG
  Serial.println("GPIO interrupts configured:");
  Serial.print("  GPIO");
  Serial.print(SYNC_RESET_PIN);
  Serial.println(": Sync reset (sequence = 0) - RISING edge");
  Serial.print("  GPIO");
  Serial.print(SYNC_COUNT_PIN);
  Serial.println(": Sync count (sequence++) - RISING edge");
  #endif

  Bluefruit.begin(0, 1);
  Bluefruit.setName("XIAO Central");

  dataService.begin();

  dataChar.setNotifyCallback(data_notify_callback);
  dataChar.begin();

  // リクエスト用Characteristicの設定
  requestChar.begin();

  Bluefruit.Central.setConnectCallback(connect_callback);
  Bluefruit.Central.setDisconnectCallback(disconnect_callback);

  Bluefruit.Scanner.setRxCallback(scan_callback);
  Bluefruit.Scanner.restartOnDisconnect(true);
  Bluefruit.Scanner.setInterval(160, 80);
  Bluefruit.Scanner.filterUuid(dataService.uuid);
  Bluefruit.Scanner.useActiveScan(false);
  Bluefruit.Scanner.start(0);

  #if ENABLE_DEBUG
  Serial.println("Scanning for peripheral...");
  #endif
}

void loop()
{
  #if AUTO_REQUEST_MODE
  // 自動リクエストモード: パルス入力なしで定期的にリクエスト
  static uint32_t lastAutoRequest = 0;
  uint32_t now = millis();
  
  if (Bluefruit.connected() && (now - lastAutoRequest >= AUTO_REQUEST_INTERVAL)) {
    lastAutoRequest = now;
    currentSequence++;
    
    #if ENABLE_DEBUG
    static uint32_t lastDebugPrint = 0;
    if (now - lastDebugPrint >= 1000) {  // 1秒ごとにデバッグ出力
      lastDebugPrint = now;
      Serial.print("[AUTO] Sequence: ");
      Serial.println(currentSequence);
    }
    #endif
    
    sendSequenceRequest();
  }
  
  #else
  // パルスモード: GPIO入力によるリクエスト
  #if ENABLE_DEBUG
  // GPIO7の状態を定期的に監視（デバッグ用）
  static uint32_t lastPinCheck = 0;
  static int lastPinState = -1;
  uint32_t now = millis();
  
  if (now - lastPinCheck >= 100) {  // 100msごとにチェック
    lastPinCheck = now;
    int currentPinState = digitalRead(SYNC_COUNT_PIN);
    if (currentPinState != lastPinState) {
      Serial.print("[GPIO] Pin ");
      Serial.print(SYNC_COUNT_PIN);
      Serial.print(" state changed to: ");
      Serial.println(currentPinState == HIGH ? "HIGH" : "LOW");
      lastPinState = currentPinState;
    }
  }
  #endif

  // シーケンスカウントが更新されたらリクエストを送信
  if (syncCountTriggered) {
    syncCountTriggered = false;
    
    #if ENABLE_DEBUG
    Serial.print("[PULSE] Count pulse detected! Sequence: ");
    Serial.println(currentSequence);
    #endif
    
    if (Bluefruit.connected()) {
      sendSequenceRequest();
    } else {
      #if ENABLE_DEBUG
      Serial.println("[WARN] Not connected, cannot send request");
      #endif
    }
  }

  // リセットがトリガーされた場合もリクエストを送信（オプション）
  if (syncResetTriggered) {
    syncResetTriggered = false;
    
    #if ENABLE_DEBUG
    Serial.print("[PULSE] Reset pulse detected! Sequence reset to: ");
    Serial.println(currentSequence);
    #endif
    
    if (Bluefruit.connected()) {
      sendSequenceRequest();
    } else {
      #if ENABLE_DEBUG
      Serial.println("[WARN] Not connected, cannot send request");
      #endif
    }
  }
  #endif
}

// シーケンス付きリクエストをSenderに送信
void sendSequenceRequest() {
  if (!requestChar.discovered()) {
    #if ENABLE_DEBUG
    Serial.println("Request characteristic not discovered");
    #endif
    return;
  }

  // リクエストパケット: シーケンス番号を送信
  uint32_t seq = currentSequence;

  #if ENABLE_DEBUG
  Serial.print("Sending request with sequence: ");
  Serial.println(seq);
  #endif

  // Writeでシーケンス番号を送信
  requestChar.write32(seq);
}

void scan_callback(ble_gap_evt_adv_report_t* report)
{
  #if ENABLE_DEBUG
  Serial.println("Found device, trying to connect...");
  #endif

  Bluefruit.Central.connect(report);
}

void connect_callback(uint16_t conn_handle)
{
  #if ENABLE_DEBUG
  Serial.println("Connected");
  Serial.println("Discovering data service ...");
  #endif

  if (!dataService.discover(conn_handle)) {
    #if ENABLE_DEBUG
    Serial.println("Data service NOT found, disconnect");
    #endif
    Bluefruit.disconnect(conn_handle);
    return;
  }

  #if ENABLE_DEBUG
  Serial.println("Data service found");
  Serial.println("Discovering data characteristic ...");
  #endif

  if (!dataChar.discover()) {
    #if ENABLE_DEBUG
    Serial.println("Data characteristic NOT found, disconnect");
    #endif
    Bluefruit.disconnect(conn_handle);
    return;
  }

  #if ENABLE_DEBUG
  Serial.println("Data characteristic found");
  #endif

  // リクエスト用Characteristicを検出
  if (!requestChar.discover()) {
    #if ENABLE_DEBUG
    Serial.println("Request characteristic NOT found (optional)");
    #endif
    // リクエスト機能がなくても継続
  } else {
    #if ENABLE_DEBUG
    Serial.println("Request characteristic found");
    #endif
  }

  BLEConnection* conn = Bluefruit.Connection(conn_handle);
  if (conn) {
    #if ENABLE_DEBUG
    Serial.println("Requesting MTU exchange...");
    #endif

    conn->requestMtuExchange(50);
    delay(100);

    #if ENABLE_DEBUG
    uint16_t mtu = conn->getMtu();
    Serial.print("MTU: ");
    Serial.println(mtu);
    #endif

    conn->requestConnectionParameter(6);
  }

  #if ENABLE_DEBUG
  Serial.println("Enable notifications ...");
  #endif

  if (dataChar.enableNotify()) {
    #if ENABLE_DEBUG
    Serial.println("Notification enabled, ready to receive data");
    Serial.println("--- DATA START ---");
    delay(100);
    #endif
  } else {
    #if ENABLE_DEBUG
    Serial.println("Failed to enable notification, disconnect");
    #endif
    Bluefruit.disconnect(conn_handle);
  }
}

void disconnect_callback(uint16_t conn_handle, uint8_t reason)
{
  (void)conn_handle;

  #if ENABLE_DEBUG
  Serial.print("Disconnected, reason=0x");
  Serial.println(reason, HEX);
  #endif
}

static uint8_t packet_buffer[24];  // シーケンス番号分を追加
static uint16_t buffer_pos = 0;
static const uint16_t PACKET_SIZE = 24;

void data_notify_callback(BLEClientCharacteristic* chr, uint8_t* data, uint16_t len)
{
  (void)chr;

  for (uint16_t i = 0; i < len; i++) {
    if (buffer_pos < PACKET_SIZE) {
      packet_buffer[buffer_pos++] = data[i];
    }

    if (buffer_pos == PACKET_SIZE) {
      Serial.write(packet_buffer, PACKET_SIZE);

      buffer_pos = 0;
    }
  }
}
