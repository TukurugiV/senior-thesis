use anyhow::{Context, Result};
use serialport::SerialPort;
use std::io::{self, Write, BufRead, BufReader};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};
use std::net::UdpSocket;

// ==== パケット仕様 ====

const PACKET_SIZE: usize = 24;  // 24バイトに変更（requestSeq追加のため）
const TARGET_FPS: f64 = 120.0;
const DT: f64 = 1.0 / TARGET_FPS;
const DEG2RAD: f64 = std::f64::consts::PI / 180.0;

// ==== IMU パケット ====

#[derive(Debug, Clone, Copy)]
struct ImuPacket {
    seq: u32,
    request_seq: u32,  // リクエストされたシーケンス番号（パルス同期用）
    gx: i16,
    gy: i16,
    gz: i16,
    ax: i16,
    ay: i16,
    az: i16,
}

impl ImuPacket {
    fn from_bytes(buf: &[u8]) -> Option<Self> {
        if buf.len() != PACKET_SIZE {
            return None;
        }

        let seq = u32::from_le_bytes([buf[2], buf[3], buf[4], buf[5]]);
        let request_seq = u32::from_le_bytes([buf[6], buf[7], buf[8], buf[9]]);
        let gx = i16::from_le_bytes([buf[10], buf[11]]);
        let gy = i16::from_le_bytes([buf[12], buf[13]]);
        let gz = i16::from_le_bytes([buf[14], buf[15]]);
        let ax = i16::from_le_bytes([buf[16], buf[17]]);
        let ay = i16::from_le_bytes([buf[18], buf[19]]);
        let az = i16::from_le_bytes([buf[20], buf[21]]);

        Some(ImuPacket {
            seq,
            request_seq,
            gx,
            gy,
            gz,
            ax,
            ay,
            az,
        })
    }
}

// ==== スケーリング ====

fn gyro_to_dps(gx: i16, gy: i16, gz: i16) -> (f64, f64, f64) {
    // 例: ±2000 dps / 16.4 LSB/dps 
    let scale = 16.384_f64;
    (gx as f64 / scale, gy as f64 / scale, gz as f64 / scale)
}

fn accel_to_g(ax: i16, ay: i16, az: i16) -> (f64, f64, f64) {
    // 例: ±4 g / 8192 LSB/g 
    let scale = 8192.0_f64;
    (ax as f64 / scale, ay as f64 / scale, az as f64 / scale)
}

// ==== シリアルバッファをクリア ====

fn clear_serial_buffer(port: &mut dyn SerialPort) -> Result<usize> {
    let mut cleared = 0usize;
    let mut buf = [0u8; 1024];
    let start_time = Instant::now();
    let max_duration = Duration::from_millis(100); // 最大100msだけクリア

    // 一定時間だけバッファをクリア
    while start_time.elapsed() < max_duration {
        match port.read(&mut buf) {
            Ok(n) if n > 0 => {
                cleared += n;
            }
            Ok(_) | Err(_) => {
                break;
            }
        }
    }

    Ok(cleared)
}

// ==== シリアルから 1 パケット取得（ヘッダ同期付き） ====

fn read_packet(port: &mut dyn SerialPort) -> Result<Option<ImuPacket>> {
    let mut byte = [0u8; 1];
    let sync_start = Instant::now();
    let sync_timeout = Duration::from_secs(1); // ヘッダ同期の最大時間

    // ヘッダ同期 (0x55, 0xAA) - タイムアウト付き
    loop {
        if sync_start.elapsed() > sync_timeout {
            return Ok(None);
        }

        match port.read_exact(&mut byte) {
            Ok(_) => {}
            Err(e) => {
                if e.kind() == std::io::ErrorKind::TimedOut {
                    return Ok(None);
                } else {
                    return Err(e.into());
                }
            }
        }

        if byte[0] == 0x55 {
            match port.read_exact(&mut byte) {
                Ok(_) => {}
                Err(e) => {
                    if e.kind() == std::io::ErrorKind::TimedOut {
                        return Ok(None);
                    } else {
                        return Err(e.into());
                    }
                }
            }
            if byte[0] == 0xAA {
                break;
            }
        }
    }

    // 残り読み込み
    let mut rest = [0u8; PACKET_SIZE - 2];
    match port.read_exact(&mut rest) {
        Ok(_) => {}
        Err(e) => {
            if e.kind() == std::io::ErrorKind::TimedOut {
                return Ok(None);
            } else {
                return Err(e.into());
            }
        }
    }

    let mut buf = [0u8; PACKET_SIZE];
    buf[0] = 0x55;
    buf[1] = 0xAA;
    buf[2..].copy_from_slice(&rest);

    Ok(ImuPacket::from_bytes(&buf))
}

// ==== クォータニオン姿勢表現 ====

#[derive(Debug, Clone, Copy)]
struct Quaternion {
    w: f64,
    x: f64,
    y: f64,
    z: f64,
}

impl Quaternion {
    fn identity() -> Self {
        Self {
            w: 1.0,
            x: 0.0,
            y: 0.0,
            z: 0.0,
        }
    }

    fn normalize(self) -> Self {
        let n = (self.w * self.w + self.x * self.x + self.y * self.y + self.z * self.z).sqrt();
        if n == 0.0 {
            Self::identity()
        } else {
            Self {
                w: self.w / n,
                x: self.x / n,
                y: self.y / n,
                z: self.z / n,
            }
        }
    }

    fn mul(self, other: Self) -> Self {
        Self {
            w: self.w * other.w - self.x * other.x - self.y * other.y - self.z * other.z,
            x: self.w * other.x + self.x * other.w + self.y * other.z - self.z * other.y,
            y: self.w * other.y - self.x * other.z + self.y * other.w + self.z * other.x,
            z: self.w * other.z + self.x * other.y - self.y * other.x + self.z * other.w,
        }
    }

    /// オイラー角 (roll, pitch, yaw) [rad] からクォータニオン生成 (Z-Y-X, yaw-pitch-roll)
    fn from_euler(roll: f64, pitch: f64, yaw: f64) -> Self {
        let cr = (roll * 0.5).cos();
        let sr = (roll * 0.5).sin();
        let cp = (pitch * 0.5).cos();
        let sp = (pitch * 0.5).sin();
        let cy = (yaw * 0.5).cos();
        let sy = (yaw * 0.5).sin();

        Self {
            w: cy * cp * cr + sy * sp * sr,
            x: cy * cp * sr - sy * sp * cr,
            y: sy * cp * sr + cy * sp * cr,
            z: sy * cp * cr - cy * sp * sr,
        }
        .normalize()
    }

    /// クォータニオン → オイラー角 (roll, pitch, yaw) [rad]
    fn to_euler(self) -> (f64, f64, f64) {
        let qw = self.w;
        let qx = self.x;
        let qy = self.y;
        let qz = self.z;

        // roll (x-axis)
        let sinr_cosp = 2.0 * (qw * qx + qy * qz);
        let cosr_cosp = 1.0 - 2.0 * (qx * qx + qy * qy);
        let roll = sinr_cosp.atan2(cosr_cosp);

        // pitch (y-axis)
        let sinp = 2.0 * (qw * qy - qz * qx);
        let pitch = if sinp.abs() >= 1.0 {
            sinp.signum() * (std::f64::consts::FRAC_PI_2)
        } else {
            sinp.asin()
        };

        // yaw (z-axis)
        let siny_cosp = 2.0 * (qw * qz + qx * qy);
        let cosy_cosp = 1.0 - 2.0 * (qy * qy + qz * qz);
        let yaw = siny_cosp.atan2(cosy_cosp);

        (roll, pitch, yaw)
    }

    /// クォータニオンから回転行列のX軸とY軸を取得（Unity用）
    fn to_rotation_vectors(self) -> ((f64, f64, f64), (f64, f64, f64)) {
        let qw = self.w;
        let qx = self.x;
        let qy = self.y;
        let qz = self.z;

        // 回転行列の計算
        // X軸方向ベクトル (ex)
        let ex_x = 1.0 - 2.0 * (qy * qy + qz * qz);
        let ex_y = 2.0 * (qx * qy + qw * qz);
        let ex_z = 2.0 * (qx * qz - qw * qy);

        // Y軸方向ベクトル (ey)
        let ey_x = 2.0 * (qx * qy - qw * qz);
        let ey_y = 1.0 - 2.0 * (qx * qx + qz * qz);
        let ey_z = 2.0 * (qy * qz + qw * qx);

        ((ex_x, ex_y, ex_z), (ey_x, ey_y, ey_z))
    }

    /// 角速度 (gx,gy,gz) [rad/s] を dt 秒積分
    fn integrate_gyro(self, gx: f64, gy: f64, gz: f64, dt: f64) -> Self {
        let dtheta_x = gx * dt;
        let dtheta_y = gy * dt;
        let dtheta_z = gz * dt;

        let theta = (dtheta_x * dtheta_x + dtheta_y * dtheta_y + dtheta_z * dtheta_z).sqrt();
        if theta < 1e-8 {
            return self;
        }

        let ux = dtheta_x / theta;
        let uy = dtheta_y / theta;
        let uz = dtheta_z / theta;

        let half = theta * 0.5;
        let sh = half.sin();

        let dq = Self {
            w: half.cos(),
            x: ux * sh,
            y: uy * sh,
            z: uz * sh,
        };

        self.mul(dq).normalize()
    }

    /// クォータニオン同士の nlerp（線形補間＋正規化）
    fn nlerp(self, other: Self, t: f64) -> Self {
        let t = t.clamp(0.0, 1.0);
        let inv_t = 1.0 - t;

        let dot = self.w * other.w + self.x * other.x + self.y * other.y + self.z * other.z;
        let (ow, ox, oy, oz) = if dot < 0.0 {
            (-other.w, -other.x, -other.y, -other.z)
        } else {
            (other.w, other.x, other.y, other.z)
        };

        Self {
            w: self.w * inv_t + ow * t,
            x: self.x * inv_t + ox * t,
            y: self.y * inv_t + oy * t,
            z: self.z * inv_t + oz * t,
        }
        .normalize()
    }
}

// ==== 加速度からチルト姿勢推定（ロール・ピッチ） ====

fn attitude_from_accel(ax: f64, ay: f64, az: f64) -> (f64, f64) {
    let roll = ay.atan2(az);
    let pitch = (-ax).atan2((ay * ay + az * az).sqrt());
    (roll, pitch)
}

// ==== クォータニオン姿勢更新 ====

fn update_orientation_quat(
    q: &mut Quaternion,
    gx_dps: f64,
    gy_dps: f64,
    gz_dps: f64,
    ax_g: f64,
    ay_g: f64,
    az_g: f64,
    dt: f64,
    alpha: f64,
) {
    // dps -> rad/s
    let gx = gx_dps * DEG2RAD;
    let gy = gy_dps * DEG2RAD;
    let gz = gz_dps * DEG2RAD;

    // 1) ジャイロで積分
    let q_gyro = q.integrate_gyro(gx, gy, gz, dt);

    // 2) 加速度が信用できるとき（静止に近い）だけチルト補正
    let norm_a = (ax_g * ax_g + ay_g * ay_g + az_g * az_g).sqrt();
    if norm_a < 0.5 || norm_a > 1.5 {
        *q = q_gyro;
        return;
    }

    // 加速度から roll/pitch 計算
    let (roll_acc, pitch_acc) = attitude_from_accel(ax_g, ay_g, az_g);

    // 現在の yaw はジャイロ積分結果から取得
    let (_, _, yaw_gyro) = q_gyro.to_euler();

    // roll/pitch は加速度、yaw はジャイロから構成したクォータニオン
    let q_acc = Quaternion::from_euler(roll_acc, pitch_acc, yaw_gyro);

    // 3) α ~ 0.98 のコンプリメンタリフィルタ (nlerp)
    *q = q_gyro.nlerp(q_acc, 1.0 - alpha);
}

// ==== キャリブレーション ====
//
// 姿勢の初期値を accel から推定し、その姿勢をクォータニオンで返す。
// ジャイロのバイアスも合わせて推定。

fn calibrate(port: &mut dyn SerialPort, duration_sec: f64) -> Result<(Quaternion, (f64, f64, f64))> {
    let start = Instant::now();

    let mut gyro_sum = (0.0_f64, 0.0_f64, 0.0_f64);
    let mut accel_sum = (0.0_f64, 0.0_f64, 0.0_f64);
    let mut count = 0usize;

    while start.elapsed().as_secs_f64() < duration_sec {
        match read_packet(port)? {
            Some(pkt) => {
                let (gx_dps, gy_dps, gz_dps) = gyro_to_dps(pkt.gx, pkt.gy, pkt.gz);
                let (ax_g, ay_g, az_g) = accel_to_g(pkt.ax, pkt.ay, pkt.az);

                gyro_sum.0 += gx_dps;
                gyro_sum.1 += gy_dps;
                gyro_sum.2 += gz_dps;

                accel_sum.0 += ax_g;
                accel_sum.1 += ay_g;
                accel_sum.2 += az_g;

                count += 1;
            }
            None => {}
        }
    }

    if count < 10 {
        return Ok((Quaternion::identity(), (0.0, 0.0, 0.0)));
    }

    let inv_n = 1.0 / (count as f64);
    let gyro_bias_dps = (
        gyro_sum.0 * inv_n,
        gyro_sum.1 * inv_n,
        gyro_sum.2 * inv_n,
    );
    let accel_mean_g = (
        accel_sum.0 * inv_n,
        accel_sum.1 * inv_n,
        accel_sum.2 * inv_n,
    );

    let (roll0, pitch0) = attitude_from_accel(accel_mean_g.0, accel_mean_g.1, accel_mean_g.2);
    let yaw0 = 0.0_f64;

    let q0 = Quaternion::from_euler(roll0, pitch0, yaw0);

    Ok((q0, gyro_bias_dps))
}

// ==== メイン ====
//
// 標準入力で "CALIBRATE" を受け取ると途中キャリブレーションを実行
// "CALIBRATION_DONE" を標準出力
//   1. 標準出力: "DATA_Q,seq,request_seq,qw,qx,qy,qz" (クォータニオン、パルス同期シーケンス付き)
//   2. UDP: "DATA,seq,request_seq,ex_x,ex_y,ex_z,ey_x,ey_y,ey_z" (Unity用回転ベクトル)

fn main() -> Result<()> {
    // コマンドライン引数からポート名を受け取る
    // 例: imu_orientation_quat.exe COM8
    let args: Vec<String> = std::env::args().collect();
    let port_name = if args.len() >= 2 {
        args[1].clone()
    } else {
        // 引数がない場合は、最初に見つかったポートを自動選択
        let ports = serialport::available_ports()
            .context("シリアルポート一覧取得に失敗しました")?;
        if ports.is_empty() {
            anyhow::bail!("利用可能なシリアルポートがありません");
        }
        ports[0].port_name.clone()
    };

    let baud = 115200;

    let mut port = serialport::new(&port_name, baud)
        .timeout(Duration::from_millis(200))
        .open()
        .with_context(|| format!("ポート {} を開けませんでした", port_name))?;

    port.write_data_terminal_ready(true)?;
    port.write_request_to_send(true)?;

    // センサーが起動するまで少し待機
    std::thread::sleep(Duration::from_millis(500));

    // 起動時キャリブレーション
    let (mut q, mut gyro_bias_dps) = calibrate(&mut *port, 2.0)?;

    // キャリブレーション後、バッファに溜まった古いデータをクリア
    clear_serial_buffer(&mut *port)?;

    let alpha = 0.98_f64;

    // ==== UDP通信設定 ====
    let unity_ip = "127.0.0.1:50005";  // UnityへデータをUDP送信
    let command_port = "127.0.0.1:50006"; // Unityからのコマンドを受信
    
    let udp_socket = UdpSocket::bind(command_port)
        .context("UDPソケットをバインドできませんでした")?;
    udp_socket.set_nonblocking(true)
        .context("UDPソケットのノンブロッキング設定に失敗しました")?;
    
    eprintln!("[INFO] UDP送信先: {}", unity_ip);
    eprintln!("[INFO] UDPコマンド受信ポート: {}", command_port);

    // 途中キャリブレーション用フラグ (スレッド間共有)
    let calibrate_flag = Arc::new(Mutex::new(false));
    let calibrate_flag_clone = Arc::clone(&calibrate_flag);
    let calibrate_flag_udp = Arc::clone(&calibrate_flag);

    // 標準入力を監視するスレッドを起動（既存機能維持）
    thread::spawn(move || {
        let stdin = io::stdin();
        let reader = BufReader::new(stdin);
        for line in reader.lines() {
            if let Ok(line) = line {
                let trimmed = line.trim().to_string();
                if trimmed == "CALIBRATE" {
                    let mut flag = calibrate_flag_clone.lock().unwrap();
                    *flag = true;
                }
            }
        }
    });

    // ====== stdout ロック & フラッシュ付き出力 ======
    let stdout = io::stdout();
    let mut out = stdout.lock();

    // Python 用ヘッダを即時送信（クォータニオン版、request_seq追加）
    writeln!(out, "# seq,request_seq,qw,qx,qy,qz")?;
    out.flush()?;

    // タイミング測定用の変数
    let mut last_packet_time: Option<Instant> = None;

    loop {
        // UDP経由のキャリブレーション要求チェック
        {
            let mut buf = [0u8; 1024];
            match udp_socket.recv_from(&mut buf) {
                Ok((len, _src)) => {
                    if let Ok(msg) = std::str::from_utf8(&buf[..len]) {
                        if msg.trim() == "CALIBRATE" {
                            let mut flag = calibrate_flag_udp.lock().unwrap();
                            *flag = true;
                            eprintln!("[INFO] Received CALIBRATE command via UDP");
                        }
                    }
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    // データなし、通常動作続行
                }
                Err(e) => {
                    eprintln!("[WARN] UDP receive error: {}", e);
                }
            }
        }

        // 途中キャリブレーション要求チェック（標準入力とUDP両方に対応）
        {
            let mut flag = calibrate_flag.lock().unwrap();
            if *flag {
                *flag = false;
                drop(flag); // ロック解放
                drop(out); // stdout ロック解放

                // キャリブレーション実行
                let (new_q, new_gyro_bias) = calibrate(&mut *port, 2.0)?;
                q = new_q;
                gyro_bias_dps = new_gyro_bias;

                // キャリブレーション後、バッファをクリア
                clear_serial_buffer(&mut *port)?;

                // タイミング変数をリセット
                last_packet_time = None;

                // stdout ロック再取得
                let stdout = io::stdout();
                out = stdout.lock();

                // キャリブレーション完了を通知（標準出力）
                writeln!(out, "CALIBRATION_DONE")?;
                out.flush()?;
                
                // キャリブレーション完了をUDP経由でもUnityに通知
                let calibration_done_msg = "CALIBRATION_DONE";
                if let Err(e) = udp_socket.send_to(calibration_done_msg.as_bytes(), unity_ip) {
                    eprintln!("[WARN] Failed to send CALIBRATION_DONE via UDP: {}", e);
                }
            }
        }

        if let Some(pkt) = read_packet(&mut *port)? {
            let now = Instant::now();

            // パケット到着間隔を測定
            let actual_dt = if let Some(last_time) = last_packet_time {
                now.duration_since(last_time).as_secs_f64()
            } else {
                DT // 初回は固定値
            };
            last_packet_time = Some(now);

            let (gx_dps_raw, gy_dps_raw, gz_dps_raw) = gyro_to_dps(pkt.gx, pkt.gy, pkt.gz);
            let (ax_g, ay_g, az_g) = accel_to_g(pkt.ax, pkt.ay, pkt.az);

            let gx_dps = gx_dps_raw - gyro_bias_dps.0;
            let gy_dps = gy_dps_raw - gyro_bias_dps.1;
            let gz_dps = gz_dps_raw - gyro_bias_dps.2;

            // 実測したdtを使用
            update_orientation_quat(
                &mut q,
                gx_dps,
                gy_dps,
                gz_dps,
                ax_g,
                ay_g,
                az_g,
                actual_dt,
                alpha,
            );

            // 1. クォータニオンを標準出力に送信（request_seq追加）
            writeln!(
                out,
                "DATA_Q,{},{},{:.9},{:.9},{:.9},{:.9}",
                pkt.seq, pkt.request_seq, q.w, q.x, q.y, q.z
            )?;
            out.flush()?;

            // 2. Unity用に回転ベクトルをUDPで送信（request_seq追加）
            let ((ex_x, ex_y, ex_z), (ey_x, ey_y, ey_z)) = q.to_rotation_vectors();
            let udp_msg = format!(
                "DATA,{},{},{:.9},{:.9},{:.9},{:.9},{:.9},{:.9}",
                pkt.seq, pkt.request_seq, ex_x, ex_y, ex_z, ey_x, ey_y, ey_z
            );
            
            if let Err(e) = udp_socket.send_to(udp_msg.as_bytes(), unity_ip) {
                // UDP送信エラーは警告のみ（Unity未起動時は無視）
                if cfg!(debug_assertions) {
                    eprintln!("[WARN] UDP send error: {}", e);
                }
            }
        }
    }
}
