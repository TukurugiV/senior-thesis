import math
import subprocess
import os
from vpython import canvas, vector, box, arrow, color, rate, label

# ========= Rust バイナリのパス =========
RUST_BIN_PATH = r"./target/release/imu_orientation_rust.exe"  # 最新ビルドを使用

# ========= 使用するシリアルポート名 =========
PORT_NAME = "COM10"  # 実環境に合わせて変更

# ========= 軸の変換設定 =========
AXIS_REMAP = [0, 2, 1]  # 必要に応じて変更
AXIS_SIGN = [1, -1, -1]   # Y軸とZ軸を逆方向に


def apply_R(R, v):
    x = R[0][0] * v[0] + R[0][1] * v[1] + R[0][2] * v[2]
    y = R[1][0] * v[0] + R[1][1] * v[1] + R[1][2] * v[2]
    z = R[2][0] * v[0] + R[2][1] * v[1] + R[2][2] * v[2]
    return (x, y, z)


def remap_axes(vec, axis_remap, axis_sign):
    return (
        vec[axis_remap[0]] * axis_sign[0],
        vec[axis_remap[1]] * axis_sign[1],
        vec[axis_remap[2]] * axis_sign[2],
    )


def quat_to_rotmat(qw, qx, qy, qz):
    """クォータニオン -> 回転行列 3x3"""

    n = math.sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
    if n == 0.0:
        qw, qx, qy, qz = 1.0, 0.0, 0.0, 0.0
    else:
        qw /= n
        qx /= n
        qy /= n
        qz /= n

    R = [[0.0] * 3 for _ in range(3)]

    R[0][0] = 1 - 2 * (qy * qy + qz * qz)
    R[0][1] = 2 * (qx * qy - qz * qw)
    R[0][2] = 2 * (qx * qz + qy * qw)

    R[1][0] = 2 * (qx * qy + qz * qw)
    R[1][1] = 1 - 2 * (qx * qx + qz * qz)
    R[1][2] = 2 * (qy * qz - qx * qw)

    R[2][0] = 2 * (qx * qz - qy * qw)
    R[2][1] = 2 * (qy * qz + qx * qw)
    R[2][2] = 1 - 2 * (qx * qx + qy * qy)

    return R


def quat_to_euler(qw, qx, qy, qz):
    """クォータニオン -> オイラー角 (roll, pitch, yaw) [rad]"""

    # roll (x-axis)
    sinr_cosp = 2 * (qw * qx + qy * qz)
    cosr_cosp = 1 - 2 * (qx * qx + qy * qy)
    roll = math.atan2(sinr_cosp, cosr_cosp)

    # pitch (y-axis)
    sinp = 2 * (qw * qy - qz * qx)
    if abs(sinp) >= 1:
        pitch = math.copysign(math.pi / 2, sinp)
    else:
        pitch = math.asin(sinp)

    # yaw (z-axis)
    siny_cosp = 2 * (qw * qz + qx * qy)
    cosy_cosp = 1 - 2 * (qy * qy + qz * qz)
    yaw = math.atan2(siny_cosp, cosy_cosp)

    return roll, pitch, yaw


def main():
    # 軸変換設定の表示
    axis_names = ["X", "Y", "Z"]
    remap_str = f"{axis_names[AXIS_REMAP[0]]}, {axis_names[AXIS_REMAP[1]]}, {axis_names[AXIS_REMAP[2]]}"
    sign_str = (
        f"{'+' if AXIS_SIGN[0] > 0 else '-'}X, "
        f"{'+' if AXIS_SIGN[1] > 0 else '-'}Y, "
        f"{'+' if AXIS_SIGN[2] > 0 else '-'}Z"
    )
    print("=" * 50)
    print("軸変換設定:")
    print(f"  AXIS_REMAP: {AXIS_REMAP} -> (X,Y,Z) → ({remap_str})")
    print(f"  AXIS_SIGN:  {AXIS_SIGN} -> {sign_str}")
    print("=" * 50)

    # Rust プロセス起動
    print(f"[DEBUG] Starting Rust process: {RUST_BIN_PATH}")
    print(f"[DEBUG] Port: {PORT_NAME}")
    
    try:
        proc = subprocess.Popen(
            [RUST_BIN_PATH, PORT_NAME],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,  # stderrもキャプチャしてエラーを確認
            text=True,
            encoding="utf-8",
            errors="ignore",
            bufsize=1,  # 行バッファ
        )
        print(f"[DEBUG] Rust process started with PID: {proc.pid}")
    except Exception as e:
        print(f"[ERROR] Failed to start Rust process: {e}")
        return

    calibrating = False
    calibration_requested = False

    # VPython シーン設定
    scene = canvas(
        title="IMU 3D Orientation (Quat)",
        width=800,
        height=600,
        center=vector(0, 0, 0),
        background=color.white,
    )
    scene.range = 2

    board = box(
        pos=vector(0, 0, 0),
        length=1.5,  # X方向
        height=1.0,  # Y方向
        width=0.1,   # Z方向
        color=color.blue,
        opacity=0.7,
    )

    x_axis = arrow(
        pos=vector(0, 0, 0),
        axis=vector(1.5, 0, 0),
        color=color.red,
        shaftwidth=0.03,
    )
    y_axis = arrow(
        pos=vector(0, 0, 0),
        axis=vector(0, 0, 1.5),
        color=color.green,
        shaftwidth=0.03,
    )
    z_axis = arrow(
        pos=vector(0, 0, 0),
        axis=vector(0, 1.5, 0),
        color=color.blue,
        shaftwidth=0.03,
    )

    label(pos=vector(1.7, 0, 0), text="X", xoffset=10, height=12, box=False)
    label(pos=vector(0, 0, 1.7), text="Y", xoffset=10, height=12, box=False)
    label(pos=vector(0, 1.7, 0), text="Z", xoffset=10, height=12, box=False)

    text_label = label(
        pos=vector(0, -1.7, 0),
        text="Roll: 0.0, Pitch: 0.0, Yaw: 0.0",
        height=14,
        box=False,
        color=color.black,
    )

    calib_label = label(
        pos=vector(0, 1.5, 0),
        text="Press 'C' to calibrate",
        height=12,
        box=True,
        color=color.black,
        background=color.yellow,
        opacity=0.8,
    )

    # キーボードイベント
    def on_keydown(evt):
        nonlocal calibration_requested
        if evt.key == "c" or evt.key == "C":
            calibration_requested = True

    scene.bind("keydown", on_keydown)

    # stdout と stderr をノンブロッキングに（UNIX 前提／Windows では不要なら削除）
    if proc.stdout:
        try:
            os.set_blocking(proc.stdout.fileno(), False)
        except Exception as e:
            print(f"[WARN] os.set_blocking for stdout failed: {e}")
    
    if proc.stderr:
        try:
            os.set_blocking(proc.stderr.fileno(), False)
        except Exception as e:
            print(f"[WARN] os.set_blocking for stderr failed: {e}")

    try:
        while True:
            rate(120)

            # キャリブレーション要求
            if calibration_requested and not calibrating:
                calibration_requested = False
                calibrating = True
                calib_label.text = "Calibrating... Keep sensor still!"
                calib_label.background = color.red

                if proc.stdin:
                    print("[DEBUG] Sending CALIBRATE...")
                    proc.stdin.write("CALIBRATE\n")
                    proc.stdin.flush()

            if proc.stdout is None:
                break

            # stderrからエラーメッセージを読み取る
            if proc.stderr:
                try:
                    while True:
                        err_line = proc.stderr.readline()
                        if not err_line:
                            break
                        print(f"[RUST STDERR] {err_line.strip()}")
                except (BlockingIOError, IOError):
                    pass

            lines = []
            try:
                while True:
                    line = proc.stdout.readline()
                    if not line:
                        break
                    lines.append(line.strip())
            except (BlockingIOError, IOError):
                pass

            if not lines:
                continue

            latest_data_line = None

            for line in reversed(lines):
                if not line:
                    continue

                # デバッグ表示（DATA_Q 以外）
                if not line.startswith("DATA_Q,") and not line.startswith("#"):
                    print(f"[DEBUG] from Rust: '{line}'")
                
                # DATA_Q行もデバッグ表示（最初の数回のみ）
                if line.startswith("DATA_Q,"):
                    if not hasattr(main, 'data_q_debug_count'):
                        main.data_q_debug_count = 0
                    if main.data_q_debug_count < 5:
                        print(f"[DEBUG] DATA_Q line: '{line}'")
                        main.data_q_debug_count += 1

                if line == "CALIBRATION_DONE":
                    print("[DEBUG] Calibration done!")
                    calibrating = False
                    calib_label.text = "Calibration Complete! Press 'C' to recalibrate"
                    calib_label.background = color.green

                if latest_data_line is None and line.startswith("DATA_Q,"):
                    latest_data_line = line

            if latest_data_line is None:
                continue

            # DATA_Q,seq,request_seq,qw,qx,qy,qz
            parts = latest_data_line.split(",")
            
            # デバッグ: パケットフォーマットを確認
            if len(parts) != 7:
                print(f"[DEBUG] Unexpected packet format: {len(parts)} fields, expected 7")
                print(f"[DEBUG] Data: {latest_data_line}")
                continue

            _, seq_s, request_seq_s, qw_s, qx_s, qy_s, qz_s = parts
            try:
                seq = int(seq_s)
                request_seq = int(request_seq_s)
                qw = float(qw_s)
                qx = float(qx_s)
                qy = float(qy_s)
                qz = float(qz_s)
            except ValueError as e:
                print(f"[DEBUG] Parse error: {e}")
                print(f"[DEBUG] Data: {latest_data_line}")
                continue

            R = quat_to_rotmat(qw, qx, qy, qz)

            ex_w = apply_R(R, (1.0, 0.0, 0.0))
            ey_w = apply_R(R, (0.0, 1.0, 0.0))

            ex_remapped = remap_axes(ex_w, AXIS_REMAP, AXIS_SIGN)
            ey_remapped = remap_axes(ey_w, AXIS_REMAP, AXIS_SIGN)

            board.axis = vector(*ex_remapped)
            board.up = vector(*ey_remapped)

            roll, pitch, yaw = quat_to_euler(qw, qx, qy, qz)
            roll_deg = math.degrees(roll)
            pitch_deg = math.degrees(pitch)
            yaw_deg = math.degrees(yaw)

            text_label.text = (
                f"Seq: {seq}  "
                f"Pulse: {request_seq}  "
                f"Roll: {roll_deg:6.2f} deg,  "
                f"Pitch: {pitch_deg:6.2f} deg,  "
                f"Yaw: {yaw_deg:6.2f} deg"
            )

    finally:
        try:
            proc.terminate()
        except Exception:
            pass


if __name__ == "__main__":
    main()
