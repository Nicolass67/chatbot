//! Non-interactive sideload CLI for Chatbot Fast Deploy.
//!
//! Commands:
//!   install  — sign + install via usbmux (USB / Network lockdown)
//!   sign     — sign only (no device) → copy .app to --out for Wi-Fi RSD install
//!
//! Exit codes:
//!   0 = OK
//!   2 = HUMAN_REQUIRED (2FA / interactive)
//!   1 = FAIL
//!
//! Env:
//!   APPLE_ID
//!   APPLE_APP_SPECIFIC_PASSWORD (or APPLE_PASSWORD)
//!   IOS_SIDELLOAD_2FA_CODE (optional one-shot code)
//!   IOS_SIDELLOAD_MACHINE_NAME (optional)
//!   IOS_INSTALL_TRANSPORT = auto|usb|wifi|network  (default: auto = USB then Wi-Fi)

use idevice::usbmuxd::{Connection, UsbmuxdAddr, UsbmuxdConnection, UsbmuxdDevice};
use isideload::{
    auth::apple_account::{TwoFactorCallbackParams, TwoFactorCallbackResponse},
    auth::builder::AppleAccountBuilder,
    auth::apple_account::AppleAccount,
    dev::developer_session::DeveloperSession,
    sideload::{
        builder::MaxCertsBehavior, SideloaderBuilder, TeamSelection,
    },
    sideload::sideloader::Sideloader,
    util::fs_storage::FsStorage,
};
use std::{
    env, fs,
    path::{Path, PathBuf},
    process,
    sync::atomic::{AtomicBool, Ordering},
};
use tracing::Level;
use tracing_subscriber::FmtSubscriber;

static NEED_HUMAN: AtomicBool = AtomicBool::new(false);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Transport {
    /// Prefer USB; fall back to usbmux Network (Wi-Fi lockdown).
    Auto,
    UsbOnly,
    WifiOnly,
}

fn exit_human(msg: &str) -> ! {
    eprintln!("HUMAN_REQUIRED: {msg}");
    process::exit(2);
}

fn exit_fail(msg: &str) -> ! {
    eprintln!("FAIL: {msg}");
    process::exit(1);
}

fn usage() -> ! {
    eprintln!(
        "Usage:\n\
         chatbot-isideload-cli install [--transport auto|usb|wifi] <path-to.ipa|.app>\n\
         chatbot-isideload-cli sign [--out <dir>] <path-to.ipa|.app>\n\
         Env: APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD (or APPLE_PASSWORD)\n\
         Env: IOS_INSTALL_TRANSPORT=auto|usb|wifi (default auto)"
    );
    process::exit(1);
}

fn parse_transport(raw: &str) -> Transport {
    match raw.trim().to_ascii_lowercase().as_str() {
        "auto" | "" => Transport::Auto,
        "usb" => Transport::UsbOnly,
        "wifi" | "network" | "wi-fi" => Transport::WifiOnly,
        other => {
            eprintln!("WARN: unknown transport '{other}', using auto");
            Transport::Auto
        }
    }
}

fn is_usb(dev: &UsbmuxdDevice) -> bool {
    matches!(dev.connection_type, Connection::Usb)
}

fn is_wifi(dev: &UsbmuxdDevice) -> bool {
    matches!(dev.connection_type, Connection::Network(_))
}

fn conn_label(dev: &UsbmuxdDevice) -> String {
    match &dev.connection_type {
        Connection::Usb => "USB".into(),
        Connection::Network(ip) => format!("Wi-Fi/{ip}"),
        Connection::Unknown(s) => format!("Unknown/{s}"),
    }
}

fn pick_device(devs: &[UsbmuxdDevice], transport: Transport) -> Option<&UsbmuxdDevice> {
    let usb = devs.iter().find(|d| is_usb(d));
    let wifi = devs.iter().find(|d| is_wifi(d));
    match transport {
        Transport::UsbOnly => usb,
        Transport::WifiOnly => wifi,
        Transport::Auto => usb.or(wifi).or_else(|| devs.first()),
    }
}

fn dirs_fallback() -> PathBuf {
    if let Ok(l) = env::var("LOCALAPPDATA") {
        return PathBuf::from(l);
    }
    env::temp_dir()
}

fn copy_dir(src: &Path, dst: &Path) -> std::io::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let ty = entry.file_type()?;
        let to = dst.join(entry.file_name());
        if ty.is_dir() {
            copy_dir(&entry.path(), &to)?;
        } else {
            fs::copy(entry.path(), to)?;
        }
    }
    Ok(())
}

fn storage_dir() -> PathBuf {
    env::var("IOS_SIDELLOAD_STORAGE")
        .map(PathBuf::from)
        .unwrap_or_else(|_| dirs_fallback().join("chatbot-isideload"))
}

async fn apple_login() -> (AppleAccount, String) {
    let apple_id = env::var("APPLE_ID").unwrap_or_default();
    let password = env::var("APPLE_APP_SPECIFIC_PASSWORD")
        .or_else(|_| env::var("APPLE_PASSWORD"))
        .unwrap_or_default();
    if apple_id.is_empty() || password.is_empty() {
        exit_human("missing APPLE_ID / APPLE_APP_SPECIFIC_PASSWORD");
    }

    let get_2fa = |_params: TwoFactorCallbackParams| async move {
        if let Ok(code) = env::var("IOS_SIDELLOAD_2FA_CODE") {
            let code = code.trim().to_string();
            if !code.is_empty() {
                return Ok(TwoFactorCallbackResponse::SubmitCode(code));
            }
        }
        NEED_HUMAN.store(true, Ordering::SeqCst);
        Ok(TwoFactorCallbackResponse::Abort)
    };

    let account = AppleAccountBuilder::new(&apple_id)
        .login(&password, get_2fa)
        .await;

    let account = match account {
        Ok(a) => a,
        Err(e) => {
            if NEED_HUMAN.load(Ordering::SeqCst) {
                exit_human("2FA required (set IOS_SIDELLOAD_2FA_CODE or use iLoader)");
            }
            exit_fail(&format!("Apple login failed: {e}"));
        }
    };

    if NEED_HUMAN.load(Ordering::SeqCst) {
        exit_human("2FA required");
    }
    (account, apple_id)
}

async fn build_sideloader_async(account: &mut AppleAccount, apple_id: String) -> Sideloader {
    let storage = storage_dir();
    let _ = fs::create_dir_all(&storage);

    let dev_session = match DeveloperSession::from_account(account).await {
        Ok(s) => s,
        Err(e) => exit_fail(&format!("DeveloperSession: {e}")),
    };

    let machine =
        env::var("IOS_SIDELLOAD_MACHINE_NAME").unwrap_or_else(|_| "chatbot-pc".to_string());

    SideloaderBuilder::new(dev_session, apple_id)
        .team_selection(TeamSelection::First)
        .max_certs_behavior(MaxCertsBehavior::Revoke)
        .storage(Box::new(FsStorage::new(storage)))
        .machine_name(machine)
        .build()
}

async fn cmd_sign(app_path: PathBuf, out_dir: PathBuf) {
    let (mut account, apple_id) = apple_login().await;
    let mut sideloader = build_sideloader_async(&mut account, apple_id).await;

    eprintln!("signing {} ...", app_path.display());
    match sideloader
        .sign_app(
            app_path,
            None,
            true,
            None::<fn(f32) -> std::future::Ready<()>>,
        )
        .await
    {
        Ok((signed_path, _special)) => {
            let _ = fs::create_dir_all(&out_dir);
            let name = signed_path
                .file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| "App.app".into());
            let dest = out_dir.join(&name);
            if dest.exists() {
                let _ = fs::remove_dir_all(&dest);
                let _ = fs::remove_file(&dest);
            }
            if signed_path.is_dir() {
                if let Err(e) = copy_dir(&signed_path, &dest) {
                    exit_fail(&format!("copy signed app: {e}"));
                }
            } else if let Err(e) = fs::copy(&signed_path, &dest) {
                exit_fail(&format!("copy signed file: {e}"));
            }
            println!("{}", dest.display());
            eprintln!("OK: signed {}", dest.display());
            process::exit(0);
        }
        Err(e) => {
            let msg = format!("{e}");
            if NEED_HUMAN.load(Ordering::SeqCst)
                || msg.to_lowercase().contains("2fa")
                || msg.contains("Abort")
            {
                exit_human(&msg);
            }
            exit_fail(&format!("sign_app: {msg}"));
        }
    }
}

async fn cmd_install(app_path: PathBuf, transport: Transport) {
    let (mut account, apple_id) = apple_login().await;
    let mut sideloader = build_sideloader_async(&mut account, apple_id).await;

    let mut usbmuxd = match UsbmuxdConnection::default().await {
        Ok(u) => u,
        Err(e) => exit_fail(&format!("usbmuxd: {e}")),
    };
    let devs = match usbmuxd.get_devices().await {
        Ok(d) => d,
        Err(e) => exit_fail(&format!("list devices: {e}")),
    };
    if devs.is_empty() {
        exit_fail(
            "no iPhone in usbmux (USB or Wi-Fi). \
             USB: plug cable + Trust. \
             Prefer Wi-Fi RSD: npm.cmd run ios:deploy:wifi",
        );
    }

    let Some(dev) = pick_device(&devs, transport) else {
        let listed = devs
            .iter()
            .map(|d| format!("{} [{}]", d.udid, conn_label(d)))
            .collect::<Vec<_>>()
            .join(", ");
        exit_fail(&format!(
            "no device matching transport={transport:?}. seen: {listed}"
        ));
    };

    println!(
        "device {} via {} (transport={transport:?})",
        dev.udid,
        conn_label(dev)
    );

    let provider =
        dev.to_provider(UsbmuxdAddr::from_env_var().unwrap(), "chatbot-isideload");

    match sideloader
        .install_app(
            &provider,
            app_path,
            true,
            None::<fn(f32) -> std::future::Ready<()>>,
        )
        .await
    {
        Ok(_) => {
            println!("OK: app installed via isideload");
            process::exit(0);
        }
        Err(e) => {
            let msg = format!("{e}");
            if msg.to_lowercase().contains("2fa") || msg.contains("Abort") {
                exit_human(&msg);
            }
            exit_fail(&format!("install_app: {msg}"));
        }
    }
}

#[tokio::main]
async fn main() {
    let _ = rustls::crypto::ring::default_provider().install_default();
    if let Err(e) = isideload::init() {
        exit_fail(&format!("isideload init: {e}"));
    }
    let _ = tracing::subscriber::set_global_default(
        FmtSubscriber::builder().with_max_level(Level::INFO).finish(),
    );

    let mut args = env::args().skip(1).collect::<Vec<_>>();
    if args.is_empty() {
        usage();
    }
    let cmd = args.remove(0);

    match cmd.as_str() {
        "sign" => {
            let mut out_dir = env::temp_dir().join("chatbot-signed-app");
            let mut path_arg: Option<String> = None;
            let mut i = 0;
            while i < args.len() {
                if args[i] == "--out" {
                    if i + 1 >= args.len() {
                        usage();
                    }
                    out_dir = PathBuf::from(&args[i + 1]);
                    i += 2;
                    continue;
                }
                if args[i].starts_with("--out=") {
                    out_dir = PathBuf::from(args[i].split_once('=').map(|(_, v)| v).unwrap_or(""));
                    i += 1;
                    continue;
                }
                if path_arg.is_none() && !args[i].starts_with('-') {
                    path_arg = Some(args[i].clone());
                }
                i += 1;
            }
            let app_path = PathBuf::from(path_arg.unwrap_or_else(|| usage()));
            if !app_path.exists() {
                exit_fail(&format!("path not found: {}", app_path.display()));
            }
            cmd_sign(app_path, out_dir).await;
        }
        "install" => {
            if args.is_empty() {
                usage();
            }
            let mut transport = parse_transport(
                &env::var("IOS_INSTALL_TRANSPORT").unwrap_or_else(|_| "auto".into()),
            );
            let mut path_arg: Option<String> = None;
            let mut i = 0;
            while i < args.len() {
                if args[i] == "--transport" {
                    if i + 1 >= args.len() {
                        usage();
                    }
                    transport = parse_transport(&args[i + 1]);
                    i += 2;
                    continue;
                }
                if args[i].starts_with("--transport=") {
                    transport =
                        parse_transport(args[i].split_once('=').map(|(_, v)| v).unwrap_or(""));
                    i += 1;
                    continue;
                }
                if path_arg.is_none() && !args[i].starts_with('-') {
                    path_arg = Some(args[i].clone());
                }
                i += 1;
            }
            let app_path = PathBuf::from(path_arg.unwrap_or_else(|| usage()));
            if !app_path.exists() {
                exit_fail(&format!("path not found: {}", app_path.display()));
            }
            cmd_install(app_path, transport).await;
        }
        _ => usage(),
    }
}
