#!/usr/bin/env python3
"""
sign.py - NextE HAP 签名安装脚本 (移植自 V2Next, 共享账号级调试签名物料)

用法:
  python3 scripts/sign.py                # 签名+安装（自动选设备/读缓存）
  python3 scripts/sign.py --no-install   # 仅签名，不安装到设备
  python3 scripts/sign.py -d all         # 安装到所有已连接设备
  python3 scripts/sign.py -d <device>    # 安装到指定设备（并更新缓存）
  python3 scripts/sign.py --force-profile # 强制重建 Profile（同 --refresh）
  python3 scripts/sign.py --refresh      # 强制刷新证书和 Profile
  python3 scripts/sign.py -h             # 显示帮助

首次为 com.erosteam.nexte 签发 Profile 需要:
  1) 一台已连接的 HarmonyOS 设备（debug profile 是设备绑定的，需要其 UDID）
  2) 华为开发者账号（脚本会打开浏览器登录；登录态缓存于
     ~/Documents/hap_installer/userInfo.json，与 V2Next 共享，已登录则免重登）
账号级调试证书 (debug.p12 / debug.csr / ohos-D.cer) 与 V2Next 复用，profile 按 bundleId 单独签发。
环境变量来自 scripts/dev.env（HARMONY_DEBUG_* 契约，与 V2Next 一致）。

设备缓存:
  首次运行若检测到多设备会提示选择，结果缓存 7 天。
"""
import sys, os, json, subprocess, time, urllib.request, urllib.error, random, webbrowser, zipfile
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler

# ── 配置 ──────────────────────────────────────────────────────────────────────
PROJ        = Path(__file__).resolve().parent.parent
SCRIPTS     = Path(__file__).resolve().parent
SDK         = Path(os.environ.get("DEVECO_SDK_HOME", "/home/gamer/devtool/ohos/command-line-tools/sdk"))
TOOL_LIB    = SDK / "default/openharmony/toolchains/lib"
HAP_SIGN    = TOOL_LIB / "hap-sign-tool.jar"
HDC         = Path(os.environ.get("HDC", str(SDK / "default/openharmony/toolchains/hdc")))
UNSIGNED_HAP = PROJ / "entry/build/default/outputs/default/entry-default-unsigned.hap"
SIGNED_HAP  = PROJ / "entry/build/default/outputs/default/entry-default-signed.hap"

BUNDLE_NAME = os.environ.get("NEXTE_BUNDLE", "com.erosteam.nexte")


def _required_env(key: str) -> str:
    v = os.environ.get(key)
    if not v:
        sys.exit(
            f"sign.py: missing required env {key}. "
            "Source scripts/dev.env first (e.g. `source scripts/dev.env` or run via dev.sh)."
        )
    return v


# 账号级共享调试签名（多 OH 项目复用同一份 cert，避免撞 AGC debug-cert 配额）
HARMONY_DEBUG_DIR = Path(_required_env("HARMONY_DEBUG_DIR"))
CERT_NAME         = _required_env("HARMONY_DEBUG_CERT_NAME")
KS_ALIAS          = _required_env("HARMONY_DEBUG_KS_ALIAS")
KS_PWD            = _required_env("HARMONY_DEBUG_KS_PWD")

KS_FILE      = HARMONY_DEBUG_DIR / "debug.p12"
CSR          = HARMONY_DEBUG_DIR / "debug.csr"
CERT_FILE    = HARMONY_DEBUG_DIR / f"{CERT_NAME}.cer"
# profile 是 per-bundleId 的，由 dev.env 显式给路径
PROFILE_FILE = Path(_required_env("HARMONY_DEBUG_PROFILE"))
REAL_HOME    = Path(os.environ.get("V2NEXT_REAL_HOME") or str(Path.home()))
# AGC 登录态缓存与 V2Next 共享（已登录过则免重登）
AUTH_FILE    = REAL_HOME / "Documents/hap_installer/userInfo.json"

# 设备选择缓存文件及有效期（7 天）
DEVICE_CACHE_FILE = Path.home() / ".cache" / "nexte_device.json"
DEVICE_CACHE_TTL  = 7 * 24 * 3600

ECO_URL = "https://cn.devecostudio.huawei.com/console/DevEcoIDE/apply?port={port}&appid=1007&code=20698961dd4f420c8b44f49010c6f0cc"
KEEP_AWAKE = SCRIPTS / "keep_awake.sh"

# ── HAP 校验 ──────────────────────────────────────────────────────────────────
def hap_bundle_name(hap_path: Path) -> str:
    with zipfile.ZipFile(hap_path) as zf:
        data = json.loads(zf.read("module.json").decode("utf-8"))
    return data.get("app", {}).get("bundleName", "")

def verify_hap_bundle_name(hap_path: Path, expected: str | None = None) -> str:
    actual = hap_bundle_name(hap_path)
    print(f"HAP 包名: {actual}")
    if expected and actual != expected:
        raise RuntimeError(f"HAP 包名不符合预期: expected={expected}, actual={actual}")
    return actual

# ── API 工具函数 ──────────────────────────────────────────────────────────────
def api(url, data=None, method=None, headers=None, auth=None, raw=False):
    method = method or ("POST" if data else "GET")
    body = json.dumps(data).encode() if data else None
    h = {"content-type": "application/json"}
    if auth:
        h["oauth2Token"] = auth.get("accessToken", "")
        h["teamId"] = h["uid"] = auth.get("userId", "")
    if headers: h.update(headers)
    req = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            text = resp.read().decode()
            if raw: return text
            try: return json.loads(text)
            except json.JSONDecodeError: return text
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read().decode()[:200]}")

def download(url, dest):
    urllib.request.urlretrieve(url, dest)

# ── 登录 ──────────────────────────────────────────────────────────────────────
class CallbackHandler(BaseHTTPRequestHandler):
    result = None
    def log_message(self, *a): pass
    def do_POST(self):
        if self.path == "/callback":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write("登录成功！请返回！".encode("utf-8"))
            CallbackHandler.result = body
        else:
            self.send_response(404); self.end_headers()

def login():
    port = random.randint(8333, 9333)
    server = HTTPServer(("127.0.0.1", port), CallbackHandler)
    server.timeout = 120
    deadline = time.time() + server.timeout
    url = ECO_URL.format(port=port)
    print(f"\n请在浏览器中完成华为账号登录:")
    print(f"  {url}\n")
    webbrowser.open(url)
    print("等待登录回调（最长 120 秒）...")
    while CallbackHandler.result is None and time.time() < deadline:
        server.handle_request()
    if CallbackHandler.result is None:
        raise RuntimeError("登录回调超时：未在 120 秒内收到华为账号登录回调")
    from urllib.parse import parse_qs, quote
    body = CallbackHandler.result
    params = parse_qs(body) if "=" in body else {}
    temp = params.get("tempToken", [body])[0] if params else body
    resp = api(f"https://cn.devecostudio.huawei.com/authrouter/auth/api/temptoken/check?site=CN&tempToken={quote(temp)}&appid=1007&version=0.0.0", method="GET")
    jwt = resp if isinstance(resp, str) else resp.get("ret", {}).get("msg", str(resp))
    user_resp = api("https://cn.devecostudio.huawei.com/authrouter/auth/api/jwToken/check", method="GET", headers={"refresh": "false", "jwtToken": jwt})
    info = (user_resp.get("userInfo") or user_resp.get("body", {}).get("userInfo") or user_resp) if isinstance(user_resp, dict) else {}
    auth = {"accessToken": info.get("accessToken"), "userId": info.get("userId") or info.get("userID"),
            "teamId": info.get("userId") or info.get("userID"), "nickName": info.get("nickName", "")}
    AUTH_FILE.parent.mkdir(parents=True, exist_ok=True)
    AUTH_FILE.write_text(json.dumps(auth, indent=2))
    print(f"登录成功: {auth['nickName']} (uid={auth['userId']})")
    return auth

def load_or_login():
    if AUTH_FILE.exists():
        auth = json.loads(AUTH_FILE.read_text())
        try:
            r = api("https://connect-api.cloud.huawei.com/api/ups/user-permission-service/v1/user-team-list",
                    method="GET", auth=auth)
            if r.get("ret", {}).get("code") == 401:
                raise RuntimeError("token expired")
            print(f"使用已缓存账号: {auth.get('nickName', auth.get('userId'))}")
            return auth
        except Exception as e:
            print(f"Token 已过期，重新登录: {e}")
    return login()

# ── 证书 ──────────────────────────────────────────────────────────────────────
def ensure_cert(auth):
    cert_list = api("https://connect-api.cloud.huawei.com/api/cps/harmony-cert-manage/v1/cert/list",
                    method="GET", auth=auth).get("certList", [])
    debug_certs = [c for c in cert_list if c.get("certType") == 1]
    existing = next((c for c in debug_certs if c.get("certName") == CERT_NAME), None)

    csr_text = CSR.read_text()

    need_create = existing is None
    # 若本地证书文件不存在，说明之前是用别的 CSR 创建的（密钥不匹配），删掉重建
    if existing is not None and not CERT_FILE.exists():
        print(f"本地证书缺失，删除 AGC 旧证书并用 debug.csr 重建...")
        api("https://connect-api.cloud.huawei.com/api/cps/harmony-cert-manage/v1/cert/delete",
            data={"certIds": [existing["id"]]}, method="DELETE", auth=auth)
        existing = None
        need_create = True

    if need_create:
        if len(cert_list) >= 3:
            debug_certs.sort(key=lambda c: c.get("expireTime", 0))
            api("https://connect-api.cloud.huawei.com/api/cps/harmony-cert-manage/v1/cert/delete",
                data={"certIds": [debug_certs[0]["id"]]}, method="DELETE", auth=auth)
        print(f"创建调试证书 '{CERT_NAME}'...")
        result = api("https://connect-api.cloud.huawei.com/api/cps/harmony-cert-manage/v1/cert/add",
                     data={"csr": csr_text, "certName": CERT_NAME, "certType": 1}, auth=auth)
        existing = result.get("harmonyCert", {})
        if not existing:
            raise RuntimeError(f"证书创建失败: {result}")

    cert_id = existing["id"]
    obj_id  = existing.get("certObjectId")
    if not CERT_FILE.exists():
        urls = api("https://connect-api.cloud.huawei.com/api/amis/app-manage/v1/objects/url/reapply",
                   data={"sourceUrls": obj_id}, auth=auth)
        url = urls.get("urlsInfo", [{}])[0].get("newUrl")
        print(f"下载证书...")
        download(url, CERT_FILE)
    print(f"证书 ID: {cert_id}, 文件: {CERT_FILE.name}")
    return cert_id

# ── 设备缓存 ──────────────────────────────────────────────────────────────────
def load_cached_device() -> str | None:
    if not DEVICE_CACHE_FILE.exists():
        return None
    try:
        data = json.loads(DEVICE_CACHE_FILE.read_text())
        if time.time() < data.get("expires", 0):
            return data.get("device")
    except Exception:
        pass
    return None

def save_cached_device(device: str):
    DEVICE_CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    DEVICE_CACHE_FILE.write_text(json.dumps({
        "device":  device,
        "expires": time.time() + DEVICE_CACHE_TTL,
    }))

def pick_device(devices: list[str]) -> str:
    if len(devices) == 1:
        print(f"使用唯一已连接设备: {devices[0]}")
        return devices[0]
    print("\n检测到多个已连接设备，请选择安装目标:")
    for i, dev in enumerate(devices):
        print(f"  [{i + 1}] {dev}")
    while True:
        choice = input(f"输入序号 (1-{len(devices)}): ").strip()
        if choice.isdigit() and 1 <= int(choice) <= len(devices):
            return devices[int(choice) - 1]
        print("无效输入，请重试")

def list_connected() -> list[str]:
    targets_result = subprocess.run([str(HDC), "list", "targets"], capture_output=True, text=True)
    return [d.strip() for d in targets_result.stdout.splitlines()
            if d.strip() and d.strip() != "[Empty]"]

def resolve_install_targets(target_device_arg: str | None) -> list[str]:
    connected = list_connected()
    if not connected:
        raise RuntimeError("无已连接设备，请检查 hdc 连接")

    if target_device_arg == "all":
        devices = connected
        cached = load_cached_device()
        if cached and cached in connected:
            save_cached_device(cached)
    elif target_device_arg:
        devices = [target_device_arg]
        save_cached_device(target_device_arg)
    else:
        cached = load_cached_device()
        if cached and cached in connected:
            print(f"使用缓存设备: {cached}")
            save_cached_device(cached)
            devices = [cached]
        else:
            if cached and cached not in connected:
                print(f"缓存设备 {cached} 当前未连接，重新选择...")
            selected = pick_device(connected)
            save_cached_device(selected)
            devices = [selected]
    return devices

# ── 设备 UDID ─────────────────────────────────────────────────────────────────
def get_udids(devices: list[str]) -> list[str]:
    udids = []
    for dev in devices:
        result = subprocess.run([str(HDC), "-t", dev, "shell", "bm", "get", "--udid"],
                                capture_output=True, text=True)
        for line in result.stdout.strip().splitlines():
            line = line.strip()
            if line and "udid of" not in line.lower() and len(line) >= 32:
                udids.append(line)
                print(f"  设备 {dev} UDID: {line}")
                break
    if not udids:
        raise RuntimeError("无法获取设备 UDID，请确保设备已连接（debug profile 是设备绑定的）")
    return udids

def ensure_device(auth, udid):
    device_list = api("https://connect-api.cloud.huawei.com/api/cps/device-manage/v1/device/list?start=1&pageSize=100&encodeFlag=0",
                      method="GET", auth=auth).get("list", [])
    if not any(d.get("udid") == udid for d in device_list):
        print(f"注册设备 {udid[:16]}...")
        api("https://connect-api.cloud.huawei.com/api/cps/device-manage/v1/device/add",
            data={"deviceName": f"nexte-dev-{udid[:10]}", "udid": udid, "deviceType": 4},
            auth=auth)
        device_list = api("https://connect-api.cloud.huawei.com/api/cps/device-manage/v1/device/list?start=1&pageSize=100&encodeFlag=0",
                          method="GET", auth=auth).get("list", [])
    device_ids = [d["id"] for d in device_list]
    print(f"设备数: {len(device_list)}")
    return device_ids

# ── Profile ───────────────────────────────────────────────────────────────────
def ensure_profile(auth, cert_id, device_ids):
    profile_name = f"nexte-debug_{BUNDLE_NAME.replace('.', '_')}"
    print(f"创建 Profile '{profile_name}'...")
    result = api("https://connect-api.cloud.huawei.com/api/cps/provision-manage/v1/ide/test/provision/add",
                 data={
                     "provisionName":     profile_name,
                     "aclPermissionList": [],
                     "deviceList":        device_ids,
                     "certList":          [cert_id],
                     "packageName":       BUNDLE_NAME,
                 }, auth=auth)
    url = result.get("provisionFileUrl")
    if not url:
        raise RuntimeError(f"Profile 创建失败: {result}")
    print("下载 Profile...")
    PROFILE_FILE.parent.mkdir(parents=True, exist_ok=True)
    download(url, PROFILE_FILE)
    print(f"Profile: {PROFILE_FILE.name}")

# ── 签名 & 安装 ───────────────────────────────────────────────────────────────
def sign_hap():
    print("签名 HAP...")
    cmd = [
        "java", "-jar", str(HAP_SIGN),
        "sign-app",
        "-mode",        "localSign",
        "-keyAlias",    KS_ALIAS,
        "-keyPwd",      KS_PWD,
        "-appCertFile", str(CERT_FILE),
        "-profileFile", str(PROFILE_FILE),
        "-inFile",      str(UNSIGNED_HAP),
        "-signAlg",     "SHA256withECDSA",
        "-keystoreFile", str(KS_FILE),
        "-keystorePwd", KS_PWD,
        "-compatibleVersion", "8",
        "-outFile",     str(SIGNED_HAP),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stdout + result.stderr
    print(output)
    if "sign-app success" not in output:
        raise RuntimeError("签名失败")

def install_hap(devices: list[str]):
    print("安装 HAP...")
    for dev in devices:
        print(f"  安装到 {dev}...")
        result = subprocess.run([str(HDC), "-t", dev, "install", str(SIGNED_HAP)],
                                capture_output=True, text=True)
        output = (result.stdout + result.stderr).strip()
        print(f"  {output}")
        if result.returncode != 0:
            raise RuntimeError(f"安装失败: device={dev}, code={result.returncode}, output={output}")
        verify_installed_bundle(dev, BUNDLE_NAME)
        keep_awake(dev)

def verify_installed_bundle(dev: str, bundle_name: str):
    result = subprocess.run([str(HDC), "-t", dev, "shell", "bm", "dump", "-n", bundle_name],
                            capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    if result.returncode != 0 or bundle_name not in output:
        raise RuntimeError(f"安装后校验失败: device={dev}, bundle={bundle_name}, output={output[:500]}")
    print(f"  已安装包校验通过: {bundle_name}")

def keep_awake(dev: str | None = None):
    if not KEEP_AWAKE.exists():
        return
    cmd = [str(KEEP_AWAKE)] + (["-t", dev] if dev else [])
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        output = (result.stdout + result.stderr).strip()
        print(f"  WARN: keep-awake failed{f' on {dev}' if dev else ''}: {output}")

# ── main ──────────────────────────────────────────────────────────────────────
def main():
    args = sys.argv[1:]

    if "-h" in args or "--help" in args:
        print(__doc__)
        sys.exit(0)

    no_install    = "--no-install"    in args
    force_profile = "--force-profile" in args or "--refresh" in args
    non_interactive = "--non-interactive" in args or os.environ.get("NEXTE_SIGN_NONINTERACTIVE") == "1"

    target_device = None
    for i, arg in enumerate(args):
        if arg == "-d" and i + 1 < len(args):
            target_device = args[i + 1]
            break

    devices = []
    if not no_install:
        print("==> 检查已连接设备...")
        devices = resolve_install_targets(target_device)
        for dev in devices:
            keep_awake(dev)

    if not UNSIGNED_HAP.exists():
        print(f"ERROR: 未找到 {UNSIGNED_HAP}，请先构建（bash dev.sh --build-only）")
        sys.exit(1)

    unsigned_bundle = verify_hap_bundle_name(UNSIGNED_HAP, BUNDLE_NAME)

    if CERT_FILE.exists() and PROFILE_FILE.exists() and not force_profile:
        print("证书和 Profile 已存在，跳过 AGC API...")
        sign_hap()
        verify_hap_bundle_name(SIGNED_HAP, unsigned_bundle)
        if not no_install:
            install_hap(devices)
        return

    if non_interactive:
        missing = [str(p) for p in (KS_FILE, CERT_FILE, PROFILE_FILE) if not p.exists()]
        raise RuntimeError("非交互签名材料缺失，拒绝触发华为登录流程: " + ", ".join(missing))

    auth = load_or_login()

    print("\n==> 确认调试证书...")
    cert_id = ensure_cert(auth)

    print("\n==> 确认设备...")
    udids = get_udids(devices if devices else list_connected())
    device_ids = set()
    for udid in udids:
        device_ids.update(ensure_device(auth, udid))
    device_ids = list(device_ids)

    print("\n==> 创建 Profile...")
    if force_profile or not PROFILE_FILE.exists():
        ensure_profile(auth, cert_id, device_ids)

    print("\n==> 签名...")
    sign_hap()
    verify_hap_bundle_name(SIGNED_HAP, unsigned_bundle)
    if not no_install:
        print("\n==> 安装...")
        install_hap(devices)

    print(f"\n==> 完成！{'已签名: ' + str(SIGNED_HAP) if no_install else ''}")

if __name__ == "__main__":
    main()
