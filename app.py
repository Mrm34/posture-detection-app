from flask import Flask, request, jsonify
import firebase_admin
from firebase_admin import credentials, db
from datetime import datetime

app = Flask(__name__)

# ---------------------------
# FIREBASE INIT
# ---------------------------
cred = credentials.Certificate("serviceAccountKey.json")
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://postureai-59c4c-default-rtdb.firebaseio.com/'
})

# ---------------------------
# HOME
# ---------------------------
@app.route('/')
def home():
    return "Posture AI API Running"

# ---------------------------
# MAIN API
# ---------------------------
@app.route('/status', methods=['GET'])
def status():

    uid = request.args.get("uid")
    posture = request.args.get("posture")
    suggestion = request.args.get("suggestion")
    is_bad = request.args.get("is_bad")

    sitting_time = request.args.get("sitting_time", 0)
    good_posture = request.args.get("good_posture", 0)
    bad_posture = request.args.get("bad_posture", 0)
    score = request.args.get("posture_score", 0)

    # ---------------------------
    # STRICT UID CHECK
    # ---------------------------
    if not uid:
        return jsonify({"error": "UID missing"}), 400

    now = datetime.now()
    today = now.strftime("%Y-%m-%d")          # e.g. 2026-06-09
    day_name = now.strftime("%A")             # e.g. Monday
    hour = now.hour                           # 0-23

    # ---------------------------
    # FIREBASE PATH
    # ---------------------------
    user_ref = db.reference(f'users/{uid}')

    # ── Current analytics (unchanged) ──
    data = {
        "last_posture": posture,
        "last_suggestion": suggestion,
        "posture_score": int(score),
        "sitting_time": int(sitting_time),
        "good_posture": int(good_posture),
        "bad_posture": int(bad_posture),
        "last_updated": now.isoformat()
    }
    user_ref.child("analytics").update(data)

    # ── Daily summary — for heatmap ──
    # Path: users/{uid}/daily/{date}
    daily_ref = user_ref.child(f"daily/{today}")
    daily_ref.update({
        "date": today,
        "day": day_name,
        "posture_score": int(score),
        "good_posture": int(good_posture),
        "bad_posture": int(bad_posture),
        "sitting_time": int(sitting_time),
        "last_updated": now.isoformat()
    })

    # ── Hourly heatmap — for heatmap grid ──
    # Path: users/{uid}/heatmap/{date}/{hour}
    heatmap_ref = user_ref.child(f"heatmap/{today}/{hour}")
    heatmap_ref.update({
        "score": int(score),
        "is_bad": is_bad == "True",
        "hour": hour,
        "timestamp": now.isoformat()
    })

    # ── Weekly scores — for weekly graph ──
    # Path: users/{uid}/weekly/{day_name}
    user_ref.child(f"weekly/{day_name}").update({
        "score": int(score),
        "date": today
    })

    # ── Raw logs (unchanged) ──
    user_ref.child("raw_logs").push({
        "posture": posture,
        "is_bad": is_bad,
        "timestamp": now.isoformat()
    })

    return jsonify({"status": "ok", "uid": uid})

# ---------------------------
# RUN
# ---------------------------
if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)
