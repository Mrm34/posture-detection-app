import cv2
import mediapipe as mp
import time
import requests
import threading
from datetime import datetime
import firebase_admin
from firebase_admin import credentials, db
from plyer import notification
import math
from collections import deque

# -------------------------
# FIREBASE SETUP
# -------------------------
try:
    cred = credentials.Certificate("serviceAccountKey.json")
    firebase_admin.initialize_app(cred, {
        'databaseURL': 'https://postureai-59c4c-default-rtdb.firebaseio.com/'
    })
    ref = db.reference('active_user')
    USER_UID = ref.get()
    if not USER_UID:
        USER_UID = "DEFAULT_UID"
except:
    USER_UID = "DEFAULT_UID"

print("Tracking UID:", USER_UID)

# -------------------------
# REALTIME UID LISTENER
# App theke user bodlale Python notun UID nebe
# -------------------------
def uid_listener(event):
    global USER_UID
    if event.data and event.data != USER_UID:
        USER_UID = event.data
        print(f"[UID UPDATED] Now tracking: {USER_UID}")

try:
    db.reference('active_user').listen(uid_listener)
except Exception as e:
    print(f"UID listener error: {e}")

API_URL = "http://127.0.0.1:5000/status"

# -------------------------
# SETTINGS
# -------------------------
ENABLE_NOTIFICATION    = True
NOTIF_COOLDOWN         = 5
last_notification_time = 0

# -------------------------
# MEDIAPIPE SETUP
# -------------------------
mp_pose = mp.solutions.pose
pose    = mp_pose.Pose(min_detection_confidence=0.5, min_tracking_confidence=0.5)
mp_draw = mp.solutions.drawing_utils

cap = cv2.VideoCapture(0)

# -------------------------
# VARIABLES
# -------------------------
session_start = time.time()
good_time  = 0
bad_time   = 0
last_time  = time.time()

last_api     = 0
API_COOLDOWN = 1.5

# Camera বন্ধ হলে সব থামানোর জন্য
is_running = True

# -------------------------
# SMOOTHING BUFFERS
# -------------------------
SMOOTH_WINDOW  = 10
CONFIRM_FRAMES = 8

z_diff_history = deque(maxlen=SMOOTH_WINDOW)
tilt_history   = deque(maxlen=SMOOTH_WINDOW)
hunch_history  = deque(maxlen=SMOOTH_WINDOW)

posture_history      = deque(maxlen=CONFIRM_FRAMES)
confirmed_posture    = "WAITING"
confirmed_suggestion = "Stand/sit in frame"
confirmed_is_bad     = False

# -------------------------
# TIME FORMATTER
# -------------------------
def format_time(seconds):
    seconds = int(seconds)
    if seconds < 60:
        return f"{seconds}s"
    elif seconds < 3600:
        m, s = divmod(seconds, 60)
        return f"{m}m {s}s"
    else:
        h, rem = divmod(seconds, 3600)
        m, s   = divmod(rem, 60)
        return f"{h}h {m}m {s}s"

# -------------------------
# DISTANCE HELPER
# -------------------------
def dist(a, b):
    return math.sqrt((a.x - b.x)**2 + (a.y - b.y)**2)

# -------------------------
# CLEANUP — camera বন্ধ হলে সব থামাবে
# -------------------------
def cleanup():
    global is_running
    is_running = False
    cap.release()
    cv2.destroyAllWindows()
    print("Session ended. Camera released.")

# -------------------------
# POSTURE ANALYZER — raw values
# -------------------------
def analyze_posture_raw(lm):
    nose  = lm[0]
    l_ear = lm[7]
    r_ear = lm[8]
    ls    = lm[11]
    rs    = lm[12]
    lh    = lm[23]
    rh    = lm[24]

    shoulder_mid_x = (ls.x + rs.x) / 2
    shoulder_mid_y = (ls.y + rs.y) / 2
    hip_mid_x      = (lh.x + rh.x) / 2
    hip_mid_y      = (lh.y + rh.y) / 2
    ear_mid_z      = (l_ear.z + r_ear.z) / 2
    shoulder_z     = (ls.z + rs.z) / 2

    shoulder_width = dist(ls, rs)
    if shoulder_width < 0.01:
        shoulder_width = 0.01

    torso_height = abs(hip_mid_y - shoulder_mid_y)
    if torso_height < 0.01:
        torso_height = 0.01

    hip_z = (lh.z + rh.z) / 2

    raw_tilt    = (ls.y - rs.y) / shoulder_width
    raw_zdiff   = (ear_mid_z - shoulder_z) / shoulder_width
    raw_hunch_a = abs(shoulder_mid_x - hip_mid_x) / torso_height
    raw_hunch_b = (shoulder_z - hip_z) / shoulder_width

    return raw_tilt, raw_zdiff, raw_hunch_a, raw_hunch_b


# -------------------------
def decide_posture(avg_tilt, avg_zdiff, avg_ha, avg_hb):

    # ── 1. SHOULDER TILT ──
    if avg_tilt > 0.20:
        return "RIGHT_LEANING", "Straighten up — leaning right", True
    if avg_tilt < -0.20:
        return "LEFT_LEANING",  "Straighten up — leaning left",  True

    if avg_ha > 0.45 or avg_hb < -0.65:
        return "HUNCHED_BACK", "Sit back, roll shoulders down & back", True

    # ── 3. FORWARD HEAD ──
    if avg_zdiff < -0.75:
        return "FORWARD_HEAD", "Pull chin back — ears over shoulders", True

    # ── 4. GOOD ──
    return "GOOD_POSTURE", "Great posture! Keep it up", False


# -------------------------
# CONFIRMED POSTURE — flickering বন্ধ
# -------------------------
def get_confirmed_posture(new_posture, new_suggestion, new_is_bad):
    global confirmed_posture, confirmed_suggestion, confirmed_is_bad

    posture_history.append((new_posture, new_suggestion, new_is_bad))

    if len(posture_history) == CONFIRM_FRAMES:
        labels = [p[0] for p in posture_history]
        if len(set(labels)) == 1:
            confirmed_posture    = posture_history[-1][0]
            confirmed_suggestion = posture_history[-1][1]
            confirmed_is_bad     = posture_history[-1][2]

    return confirmed_posture, confirmed_suggestion, confirmed_is_bad


# -------------------------
# SEND DATA
# -------------------------
def send_data(posture, suggestion, is_bad):
    # is_running False হলে আর data পাঠাবে না
    if not is_running:
        return
    try:
        session = time.time() - session_start
        requests.get(API_URL, params={
            "uid":           USER_UID,
            "posture":       posture,
            "suggestion":    suggestion,
            "is_bad":        is_bad,
            "sitting_time":  int(session),
            "good_posture":  int(good_time),
            "bad_posture":   int(bad_time),
            "posture_score": int((good_time / max(session, 1)) * 100),
        }, timeout=2)
    except:
        pass


# -------------------------
# MAIN LOOP
# -------------------------
while is_running:
    ret, frame = cap.read()

    # Camera বন্ধ বা disconnect হলে
    if not ret:
        print("Camera disconnected.")
        cleanup()
        break

    frame = cv2.resize(frame, (700, 500))
    frame = cv2.flip(frame, 1)

    rgb    = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    result = pose.process(rgb)

    posture    = "WAITING"
    suggestion = "Stand/sit in frame"
    is_bad     = False

    now = time.time()
    dt  = now - last_time
    last_time = now

    if result.pose_landmarks:
        lm = result.pose_landmarks.landmark

        # Step 1: raw values
        raw_tilt, raw_zdiff, raw_ha, raw_hb = analyze_posture_raw(lm)

        # Step 2: history তে জমা
        tilt_history.append(raw_tilt)
        z_diff_history.append(raw_zdiff)
        hunch_history.append((raw_ha, raw_hb))

        # Step 3: average
        avg_tilt  = sum(tilt_history)  / len(tilt_history)
        avg_zdiff = sum(z_diff_history) / len(z_diff_history)
        avg_ha    = sum(h[0] for h in hunch_history) / len(hunch_history)
        avg_hb    = sum(h[1] for h in hunch_history) / len(hunch_history)

        # Step 4: posture সিদ্ধান্ত
        raw_posture, raw_suggestion, raw_is_bad = decide_posture(
            avg_tilt, avg_zdiff, avg_ha, avg_hb
        )

        # Step 5: consecutive frame confirm
        posture, suggestion, is_bad = get_confirmed_posture(
            raw_posture, raw_suggestion, raw_is_bad
        )

        # ── TIME TRACKING ──
        if is_bad:
            bad_time  += dt
        else:
            good_time += dt

        # ── NOTIFICATION — is_running চেক করে তারপর notify ──
        if ENABLE_NOTIFICATION and is_bad and is_running:
            if time.time() - last_notification_time > NOTIF_COOLDOWN:
                try:
                    notification.notify(
                        title="Posture Alert",
                        message=suggestion,
                        timeout=2
                    )
                    last_notification_time = time.time()
                except:
                    pass

        # ── API SEND ──
        if now - last_api > API_COOLDOWN:
            threading.Thread(
                target=send_data,
                args=(posture, suggestion, is_bad),
                daemon=True
            ).start()
            last_api = now

        mp_draw.draw_landmarks(
            frame, result.pose_landmarks, mp_pose.POSE_CONNECTIONS
        )

    # ── HUD DISPLAY ──
    session_time = int(time.time() - session_start)
    is_good = "GOOD" in posture

    cv2.putText(frame, f"Status: {posture}", (20, 40),
                cv2.FONT_HERSHEY_SIMPLEX, 0.75,
                (0, 255, 0) if is_good else (0, 0, 255), 2)

    cv2.putText(frame, f"Session: {format_time(session_time)}", (20, 80),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)

    cv2.putText(frame, f"Good: {format_time(good_time)}", (20, 120),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)

    cv2.putText(frame, f"Bad: {format_time(bad_time)}", (20, 160),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)

    cv2.putText(frame, f"Tip: {suggestion}", (20, 200),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 255, 255), 2)

    cv2.imshow("Posture AI System", frame)

    # ── Q চাপলে বা window বন্ধ করলে exit ──
    key = cv2.waitKey(1) & 0xFF
    if key == ord('q'):
        print("Quit by user.")
        cleanup()
        break

    # Window manually বন্ধ করলেও exit
    if cv2.getWindowProperty("Posture AI System", cv2.WND_PROP_VISIBLE) < 1:
        print("Window closed.")
        cleanup()
        break