//! Lingxi Desk: one-click server deploy from the desktop app.
//!
//! Logs in to a Linux machine over SSH (password or key), uploads the
//! rustdesk-server programs (hbbs + hbbr) that ship with the app, installs
//! them as systemd services and reads back the server's public key.
//!
//! Flutter talks to this through three C functions so no bridge regeneration
//! is needed: `lingxi_deploy_start`, `lingxi_deploy_poll` and
//! `lingxi_free_cstring`. The password is only kept in memory for the
//! duration of the deploy and is never logged or stored.

use std::{
    ffi::{CStr, CString},
    os::raw::c_char,
    path::PathBuf,
    sync::{Arc, Mutex},
    time::Duration,
};

use hbb_common::{anyhow, log, tokio};
use russh::{client, keys, ChannelMsg, Disconnect};
use serde_derive::{Deserialize, Serialize};

/// rustdesk-server version the bundled programs come from.
pub const SERVER_VERSION: &str = "1.1.16";
/// Where the programs are downloaded from when the app has none bundled.
const DOWNLOAD_BASE: &str =
    "https://github.com/Allen-1002/lingxi-desk/releases/download/server-1.1.16";
const REMOTE_TGZ: &str = "/tmp/lingxi-server.tgz";
const REMOTE_SCRIPT: &str = "/tmp/lingxi-server-install.sh";

#[derive(Deserialize, Default)]
struct Request {
    host: String,
    #[serde(default)]
    port: u16,
    #[serde(default)]
    user: String,
    #[serde(default)]
    password: String,
    #[serde(default)]
    key_path: String,
    #[serde(default)]
    key_passphrase: String,
}

#[derive(Serialize, Default, Clone)]
struct Status {
    running: bool,
    done: bool,
    ok: bool,
    log: Vec<String>,
    error: String,
    /// The server's public key, set on success.
    key: String,
    /// Address to use as the server, set on success.
    host: String,
    /// TCP ports that could not be reached from this computer after deploy.
    closed_ports: Vec<u16>,
    /// SHA-256 fingerprint of the SSH host key that was accepted.
    host_fingerprint: String,
}

lazy_static::lazy_static! {
    static ref STATUS: Arc<Mutex<Status>> = Default::default();
}

fn say(line: impl Into<String>) {
    let line = line.into();
    log::info!("lingxi deploy: {line}");
    STATUS.lock().unwrap().log.push(line);
}

/// Start a deploy. `req` is a JSON [Request]. Returns 0 when started,
/// 1 when one is already running, -1 on a bad request.
#[no_mangle]
pub extern "C" fn lingxi_deploy_start(req: *const c_char) -> i32 {
    if req.is_null() {
        return -1;
    }
    let text = unsafe { CStr::from_ptr(req) }.to_string_lossy().to_string();
    let Ok(mut req) = serde_json::from_str::<Request>(&text) else {
        return -1;
    };
    req.host = req.host.trim().to_owned();
    if req.host.is_empty() {
        return -1;
    }
    if req.port == 0 {
        req.port = 22;
    }
    if req.user.trim().is_empty() {
        req.user = "root".to_owned();
    }
    {
        let mut st = STATUS.lock().unwrap();
        if st.running {
            return 1;
        }
        *st = Status {
            running: true,
            ..Default::default()
        };
    }
    std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build();
        let result = match rt {
            Ok(rt) => rt.block_on(deploy(req)),
            Err(e) => Err(anyhow::anyhow!("{e}")),
        };
        let mut st = STATUS.lock().unwrap();
        st.running = false;
        st.done = true;
        match result {
            Ok(()) => st.ok = true,
            Err(e) => {
                log::warn!("lingxi deploy failed: {e:#}");
                st.error = format!("{e:#}");
            }
        }
    });
    0
}

/// Current deploy status as JSON. Free the result with [lingxi_free_cstring].
#[no_mangle]
pub extern "C" fn lingxi_deploy_poll() -> *mut c_char {
    let json = serde_json::to_string(&*STATUS.lock().unwrap()).unwrap_or_default();
    CString::new(json).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn lingxi_free_cstring(p: *mut c_char) {
    if !p.is_null() {
        unsafe { drop(CString::from_raw(p)) };
    }
}

struct Handler {
    fingerprint: Arc<Mutex<String>>,
}

impl client::Handler for Handler {
    type Error = russh::Error;

    // Trust on first use: the fingerprint is shown to the user afterwards.
    async fn check_server_key(
        &mut self,
        key: &keys::ssh_key::PublicKey,
    ) -> Result<bool, Self::Error> {
        *self.fingerprint.lock().unwrap() =
            key.fingerprint(keys::HashAlg::Sha256).to_string();
        Ok(true)
    }
}

struct Ssh {
    handle: client::Handle<Handler>,
}

impl Ssh {
    /// Run `cmd`, feeding `stdin` if given. Returns (exit code, stdout+stderr).
    async fn run(&self, cmd: &str, stdin: Option<&[u8]>) -> anyhow::Result<(u32, String)> {
        let mut ch = self.handle.channel_open_session().await?;
        ch.exec(true, cmd).await?;
        if let Some(data) = stdin {
            ch.data(data).await?;
        }
        ch.eof().await?;
        let mut out = Vec::new();
        let mut code = None;
        while let Some(msg) = ch.wait().await {
            match msg {
                ChannelMsg::Data { ref data } => out.extend_from_slice(data),
                ChannelMsg::ExtendedData { ref data, .. } => out.extend_from_slice(data),
                ChannelMsg::ExitStatus { exit_status } => code = Some(exit_status),
                _ => {}
            }
        }
        Ok((code.unwrap_or(255), String::from_utf8_lossy(&out).to_string()))
    }
}

fn default_key_paths() -> Vec<PathBuf> {
    let Some(home) = dirs_home() else {
        return vec![];
    };
    ["id_ed25519", "id_ecdsa", "id_rsa"]
        .iter()
        .map(|n| home.join(".ssh").join(n))
        .filter(|p| p.exists())
        .collect()
}

fn dirs_home() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(PathBuf::from)
}

async fn login(req: &Request, fingerprint: Arc<Mutex<String>>) -> anyhow::Result<Ssh> {
    let config = Arc::new(client::Config {
        inactivity_timeout: Some(Duration::from_secs(120)),
        ..Default::default()
    });
    let addr = (req.host.as_str(), req.port);
    let mut handle = tokio::time::timeout(
        Duration::from_secs(15),
        client::connect(config, addr, Handler { fingerprint }),
    )
    .await
    .map_err(|_| anyhow::anyhow!("连接 {}:{} 超时，请检查地址和 SSH 端口", req.host, req.port))?
    .map_err(|e| anyhow::anyhow!("连不上 {}:{}：{e}", req.host, req.port))?;

    // Keys first (the one chosen, else the usual ones in ~/.ssh), then password.
    let keys: Vec<PathBuf> = if !req.key_path.trim().is_empty() {
        vec![PathBuf::from(req.key_path.trim())]
    } else if req.password.is_empty() {
        default_key_paths()
    } else {
        vec![]
    };
    for path in keys {
        let pass = (!req.key_passphrase.is_empty()).then_some(req.key_passphrase.as_str());
        let key = match keys::load_secret_key(&path, pass) {
            Ok(k) => k,
            Err(e) => {
                if !req.key_path.trim().is_empty() {
                    anyhow::bail!("读不了密钥文件：{e}");
                }
                continue;
            }
        };
        let hash = handle.best_supported_rsa_hash().await.ok().flatten().flatten();
        let res = handle
            .authenticate_publickey(
                req.user.clone(),
                keys::PrivateKeyWithHashAlg::new(Arc::new(key), hash),
            )
            .await?;
        if res.success() {
            say(format!("已用密钥登录 {}@{}", req.user, req.host));
            return Ok(Ssh { handle });
        }
    }
    if !req.password.is_empty() {
        let res = handle
            .authenticate_password(req.user.clone(), req.password.clone())
            .await?;
        if res.success() {
            say(format!("已用密码登录 {}@{}", req.user, req.host));
            return Ok(Ssh { handle });
        }
        anyhow::bail!("用户名或密码不对");
    }
    anyhow::bail!("登录失败：密钥不被接受，也没有填密码")
}

/// Bundled programs for `arch` (amd64 / arm64), next to the app.
fn bundled_tgz(arch: &str) -> Option<PathBuf> {
    let name = format!("lingxi-server-linux-{arch}.tar.gz");
    let exe = std::env::current_exe().ok()?;
    let dir = exe.parent()?;
    [
        dir.join("lingxi-server").join(&name),
        dir.join("../Resources/lingxi-server").join(&name),
    ]
    .into_iter()
    .find(|p| p.exists())
}

async fn server_programs(arch: &str) -> anyhow::Result<Vec<u8>> {
    if let Some(p) = bundled_tgz(arch) {
        return Ok(std::fs::read(p)?);
    }
    let url = format!("{DOWNLOAD_BASE}/lingxi-server-linux-{arch}.tar.gz");
    say("安装包里没有服务器程序，正在从 GitHub 下载…");
    let resp = reqwest::Client::builder()
        .timeout(Duration::from_secs(120))
        .build()?
        .get(&url)
        .send()
        .await?
        .error_for_status()?;
    Ok(resp.bytes().await?.to_vec())
}

fn install_script() -> &'static str {
    r#"set -e
HOST="$1"
D=/opt/lingxi-server
if ! command -v systemctl >/dev/null 2>&1; then
  echo "这台服务器没有 systemd，暂不支持一键部署" >&2; exit 3
fi
if ! id lingxi >/dev/null 2>&1; then
  useradd --system --home-dir "$D" --shell /usr/sbin/nologin lingxi 2>/dev/null \
    || useradd -r -d "$D" -s /sbin/nologin lingxi
fi
mkdir -p "$D/data"
systemctl stop lingxi-hbbs lingxi-hbbr >/dev/null 2>&1 || true
tar xzf /tmp/lingxi-server.tgz -C "$D" hbbs hbbr
chown root:root "$D/hbbs" "$D/hbbr"
chmod 755 "$D/hbbs" "$D/hbbr"
chown -R lingxi:lingxi "$D/data"
chmod 700 "$D/data"
unit() {
cat > "/etc/systemd/system/lingxi-$1.service" <<EOF
[Unit]
Description=Lingxi Desk $1
After=network-online.target
Wants=network-online.target

[Service]
User=lingxi
Group=lingxi
WorkingDirectory=$D/data
ExecStart=$D/$1 $2
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}
unit hbbs "-r $HOST:21117 -k _"
unit hbbr "-k _"
systemctl daemon-reload
systemctl enable lingxi-hbbs lingxi-hbbr >/dev/null 2>&1
systemctl restart lingxi-hbbs lingxi-hbbr
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 21115:21119/tcp >/dev/null; ufw allow 21116/udp >/dev/null
  echo "已在 ufw 防火墙放行端口"
fi
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=21115-21119/tcp --add-port=21116/udp >/dev/null
  firewall-cmd --reload >/dev/null
  echo "已在 firewalld 防火墙放行端口"
fi
for i in $(seq 1 30); do [ -s "$D/data/id_ed25519.pub" ] && break; sleep 0.5; done
rm -f /tmp/lingxi-server.tgz /tmp/lingxi-server-install.sh
systemctl is-active --quiet lingxi-hbbs || { echo "hbbs 没有启动成功" >&2; journalctl -u lingxi-hbbs -n 20 --no-pager >&2; exit 4; }
systemctl is-active --quiet lingxi-hbbr || { echo "hbbr 没有启动成功" >&2; journalctl -u lingxi-hbbr -n 20 --no-pager >&2; exit 4; }
echo "LINGXI_KEY=$(cat "$D/data/id_ed25519.pub")"
"#
}

fn shell_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

async fn deploy(req: Request) -> anyhow::Result<()> {
    say(format!("正在连接 {}:{}…", req.host, req.port));
    let fingerprint = Arc::new(Mutex::new(String::new()));
    let ssh = login(&req, fingerprint.clone()).await?;
    STATUS.lock().unwrap().host_fingerprint = fingerprint.lock().unwrap().clone();

    let (_, out) = ssh.run("uname -s; uname -m; id -u", None).await?;
    let mut lines = out.lines();
    let os = lines.next().unwrap_or("").trim().to_owned();
    let machine = lines.next().unwrap_or("").trim().to_owned();
    let uid = lines.next().unwrap_or("").trim().to_owned();
    if os != "Linux" {
        anyhow::bail!("只支持 Linux 服务器（这台是 {os}）");
    }
    let arch = match machine.as_str() {
        "x86_64" | "amd64" => "amd64",
        "aarch64" | "arm64" => "arm64",
        other => anyhow::bail!("不支持这种服务器架构：{other}"),
    };
    say(format!("服务器是 Linux {machine}"));

    let tgz = server_programs(arch).await?;
    say(format!(
        "正在上传服务器程序（{:.1} MB）…",
        tgz.len() as f64 / 1024.0 / 1024.0
    ));
    let (code, out) = ssh
        .run(&format!("cat > {REMOTE_TGZ}"), Some(&tgz))
        .await?;
    if code != 0 {
        anyhow::bail!("上传失败：{}", out.trim());
    }
    let (code, out) = ssh
        .run(
            &format!("cat > {REMOTE_SCRIPT}"),
            Some(install_script().as_bytes()),
        )
        .await?;
    if code != 0 {
        anyhow::bail!("上传失败：{}", out.trim());
    }

    say("正在安装并启动服务…");
    let run = format!("bash {REMOTE_SCRIPT} {}", shell_quote(&req.host));
    let (code, out) = if uid == "0" {
        ssh.run(&run, None).await?
    } else if !req.password.is_empty() {
        let pw = format!("{}\n", req.password);
        ssh.run(&format!("sudo -S -p '' {run}"), Some(pw.as_bytes()))
            .await?
    } else {
        ssh.run(&format!("sudo -n {run}"), None).await?
    };
    let mut key = String::new();
    for line in out.lines() {
        if let Some(k) = line.strip_prefix("LINGXI_KEY=") {
            key = k.trim().to_owned();
        } else if !line.trim().is_empty() && code == 0 {
            say(line.trim());
        }
    }
    if code != 0 {
        let msg = out.trim();
        if uid != "0" && (msg.contains("password") || msg.contains("sudo")) {
            anyhow::bail!("这个用户没有管理员权限（sudo），请用 root 或能 sudo 的用户：{msg}");
        }
        anyhow::bail!("安装失败：{msg}");
    }
    if key.is_empty() {
        anyhow::bail!("服务已启动，但没读到服务器公钥");
    }
    let _ = ssh
        .handle
        .disconnect(Disconnect::ByApplication, "", "zh")
        .await;
    say("服务已启动");

    // Check from this computer which TCP ports are reachable.
    say("正在检查端口能不能从这台电脑连上…");
    let mut closed = vec![];
    for port in 21115u16..=21119 {
        let ok = tokio::time::timeout(
            Duration::from_secs(4),
            tokio::net::TcpStream::connect((req.host.as_str(), port)),
        )
        .await
        .map(|r| r.is_ok())
        .unwrap_or(false);
        if !ok {
            closed.push(port);
        }
    }
    let mut st = STATUS.lock().unwrap();
    st.key = key;
    st.host = req.host.clone();
    st.closed_ports = closed;
    Ok(())
}
