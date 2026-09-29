# -*- coding: utf-8 -*-
"""
أداة البائع لإصدار مفاتيح تفعيل «نادي جيم» (لا تُسلَّم للزبائن أبداً).

التشغيل بدون أوامر يفتح أسئلة بسيطة (يكفي النقر مرتين على license_tool.bat في ويندوز):
    python tools/license_tool.py

الأوامر:
    python tools/license_tool.py init
        مرة واحدة فقط: يولّد زوج مفاتيح RSA-2048.
        - المفتاح الخاص يُحفظ في مجلدك الشخصي: ~/.nadi_gym_license/private_key.json
          احتفظ بنسخة منه في مكان آمن؛ إن فقدته لن تستطيع إصدار مفاتيح للنسخ الموزعة.
        - المفتاح العام يُكتب في lib/core/license_pubkey.dart (ارفعه إلى GitHub ليُبنى معه التطبيق).

    python tools/license_tool.py issue --device ABCD-EFGH-JKLM --tier pro --gym "نادي القوة" --months 12
    python tools/license_tool.py issue --device ABCD-EFGH-JKLM --tier plus --gym "نادي القوة"           (دائم)

    python tools/license_tool.py verify "NG1...."

    --key-file مسار آخر للمفتاح الخاص (مثلاً من فلاشة)
"""

import argparse
import base64
import csv
import hashlib
import json
import os
import secrets
import sys
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DIR = os.path.join(os.path.expanduser("~"), ".nadi_gym_license")
DEFAULT_KEY = os.path.join(DEFAULT_DIR, "private_key.json")
PUBKEY_DART = os.path.join(ROOT, "lib", "core", "license_pubkey.dart")
LOG_FILE = os.path.join(DEFAULT_DIR, "issued_keys.csv")
PREFIX = "NG1"
TIERS = ("plus", "pro")

_SHA256_PREFIX = bytes.fromhex("3031300d060960864801650304020105000420")
_SMALL_PRIMES = [p for p in range(3, 2000) if all(p % q for q in range(2, int(p ** 0.5) + 1))]


# ---------------------------------------------------------------------------
# RSA بدون مكتبات خارجية
# ---------------------------------------------------------------------------

def _is_probable_prime(n, rounds=40):
    if n < 2:
        return False
    for p in _SMALL_PRIMES:
        if n % p == 0:
            return n == p
    d, r = n - 1, 0
    while d % 2 == 0:
        d //= 2
        r += 1
    for _ in range(rounds):
        a = secrets.randbelow(n - 3) + 2
        x = pow(a, d, n)
        if x in (1, n - 1):
            continue
        for _ in range(r - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True


def _prime(bits):
    while True:
        c = secrets.randbits(bits) | (1 << (bits - 1)) | (1 << (bits - 2)) | 1
        if _is_probable_prime(c):
            return c


def generate_keypair(bits=2048):
    e = 65537
    while True:
        p, q = _prime(bits // 2), _prime(bits // 2)
        if p == q:
            continue
        phi = (p - 1) * (q - 1)
        if phi % e == 0:
            continue
        n = p * q
        if n.bit_length() != bits:
            continue
        return {"n": n, "e": e, "d": pow(e, -1, phi)}


def _encoded_digest(payload, k):
    t = _SHA256_PREFIX + hashlib.sha256(payload).digest()
    return int.from_bytes(b"\x00\x01" + b"\xff" * (k - len(t) - 3) + b"\x00" + t, "big")


def sign(payload, key):
    k = (key["n"].bit_length() + 7) // 8
    return pow(_encoded_digest(payload, k), key["d"], key["n"]).to_bytes(k, "big")


def verify(payload, sig, key):
    k = (key["n"].bit_length() + 7) // 8
    if len(sig) != k:
        return False
    s = int.from_bytes(sig, "big")
    return s < key["n"] and pow(s, key["e"], key["n"]) == _encoded_digest(payload, k)


def _b64e(b):
    return base64.urlsafe_b64encode(b).decode("ascii").rstrip("=")


def _b64d(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def normalize_device(code):
    c = "".join(ch for ch in (code or "").upper() if ch.isalnum())
    return "-".join(c[i:i + 4] for i in range(0, len(c), 4))


# ---------------------------------------------------------------------------

def load_key(path):
    if not os.path.exists(path):
        sys.exit(f"لم يُعثر على المفتاح الخاص: {path}\nشغّل أولاً: python tools/license_tool.py init")
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)
    return {k: int(v) for k, v in raw.items() if k in ("n", "e", "d")}


def write_pubkey_dart(key):
    os.makedirs(os.path.dirname(PUBKEY_DART), exist_ok=True)
    with open(PUBKEY_DART, "w", encoding="utf-8") as f:
        f.write("// المفتاح العام للتحقق من مفاتيح التفعيل (مولّد بـ tools/license_tool.py init).\n")
        f.write("// آمن للنشر: لا يمكن إصدار مفاتيح به. المفتاح الخاص عند البائع فقط.\n")
        f.write(f"final BigInt licensePublicN = BigInt.parse('{key['n']}');\n")
        f.write(f"final BigInt licensePublicE = BigInt.from({key['e']});\n")


def cmd_init(args):
    path = args.key_file
    if os.path.exists(path) and not args.force:
        sys.exit(f"يوجد مفتاح خاص مسبقاً في {path}\nإنشاء مفتاح جديد يُبطل كل المفاتيح التي أصدرتها. استخدم --force إن كنت متأكداً.")
    print("جاري توليد المفاتيح (قد يستغرق دقيقة)...")
    key = generate_keypair()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump({k: str(v) for k, v in key.items()}, f)
    write_pubkey_dart(key)
    print(f"✓ المفتاح الخاص: {path}  (احتفظ بنسخة احتياطية منه!)")
    print(f"✓ المفتاح العام: {PUBKEY_DART}  (ارفعه إلى GitHub ليُبنى معه التطبيق)")


def make_key(key, device, tier, gym, expires=None):
    data = {
        "device": normalize_device(device),
        "tier": tier,
        "gym": gym or "",
        "expires": expires or "",
        "issued": date.today().isoformat(),
        "id": secrets.token_hex(4),
    }
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return f"{PREFIX}.{_b64e(payload)}.{_b64e(sign(payload, key))}", data


def _add_months(d, months):
    m = d.month - 1 + months
    y = d.year + m // 12
    m = m % 12 + 1
    import calendar
    return date(y, m, min(d.day, calendar.monthrange(y, m)[1]))


def cmd_issue(args):
    key = load_key(args.key_file)
    if args.tier not in TIERS:
        sys.exit("الباقة يجب أن تكون plus أو pro")
    dev = normalize_device(args.device)
    if len(dev.replace("-", "")) < 8:
        sys.exit("رمز الجهاز غير صحيح (يظهر للزبون في: الإعدادات › الترخيص)")
    expires = args.expires
    if not expires and args.months:
        expires = _add_months(date.today(), args.months).isoformat()
    lic, data = make_key(key, dev, args.tier, args.gym, expires)
    os.makedirs(DEFAULT_DIR, exist_ok=True)
    new = not os.path.exists(LOG_FILE)
    with open(LOG_FILE, "a", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["التاريخ", "النادي", "الجهاز", "الباقة", "حتى", "المعرّف", "المفتاح"])
        w.writerow([data["issued"], data["gym"], data["device"], data["tier"], data["expires"] or "دائم", data["id"], lic])
    print("\nمفتاح التفعيل (أرسله للزبون كما هو):\n")
    print(lic)
    print(f"\nالنادي: {data['gym']} | الجهاز: {data['device']} | الباقة: {data['tier']} | حتى: {data['expires'] or 'دائم'}")
    return lic


def cmd_verify(args):
    key = load_key(args.key_file)
    parts = "".join(args.key.split()).split(".")
    if len(parts) != 3 or parts[0] != PREFIX:
        sys.exit("صيغة غير صحيحة")
    payload, sig = _b64d(parts[1]), _b64d(parts[2])
    print("✓ صالح" if verify(payload, sig, key) else "✗ غير صالح")
    print(json.loads(payload.decode("utf-8")))


def interactive(key_file):
    if not os.path.exists(key_file):
        print("لا يوجد مفتاح خاص بعد. سيتم إنشاؤه الآن (مرة واحدة فقط).")
        cmd_init(argparse.Namespace(key_file=key_file, force=False))
    print("\n=== إصدار مفتاح تفعيل نادي جيم ===")
    device = input("رمز جهاز الزبون (من شاشة الترخيص عنده): ").strip()
    gym = input("اسم النادي: ").strip()
    tier = (input("الباقة [plus / pro] (pro): ").strip().lower() or "pro")
    months = input("المدة بالأشهر (فارغ = دائم): ").strip()
    cmd_issue(argparse.Namespace(key_file=key_file, device=device, gym=gym, tier=tier,
                                 months=int(months) if months.isdigit() else None, expires=None))
    input("\nاضغط Enter للإغلاق...")


def main(argv=None):
    ap = argparse.ArgumentParser(description="مفاتيح تفعيل نادي جيم")
    ap.add_argument("--key-file", default=DEFAULT_KEY)
    sub = ap.add_subparsers(dest="cmd")
    p = sub.add_parser("init")
    p.add_argument("--force", action="store_true")
    p = sub.add_parser("issue")
    p.add_argument("--device", required=True)
    p.add_argument("--tier", required=True, choices=TIERS)
    p.add_argument("--gym", default="")
    p.add_argument("--months", type=int)
    p.add_argument("--expires", help="YYYY-MM-DD")
    p = sub.add_parser("verify")
    p.add_argument("key")
    args = ap.parse_args(argv)
    if args.cmd == "init":
        cmd_init(args)
    elif args.cmd == "issue":
        cmd_issue(args)
    elif args.cmd == "verify":
        cmd_verify(args)
    else:
        interactive(args.key_file)


if __name__ == "__main__":
    if sys.platform == "win32":
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except Exception:
            pass
    main()
