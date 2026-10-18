//! The servers this computer paired with, ported from the Mac's `PairedMachine` and its Keychain store.
//! Each record holds this computer's Noise private key for that server and its rly_ token, so it lives
//! in the system's credential store through `keyring` and never reaches the webview: the pages see only
//! a summary with no secret in it.

#[cfg(test)]
use std::collections::HashMap;
#[cfg(test)]
use std::sync::Mutex;

use serde::{Deserialize, Serialize};

/// Everything kept about one server reached over the relay.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PairedServer {
    pub machine_id: String,
    pub machine: String,
    pub relay_url: String,
    /// Base64url, as remote-contract.md writes mailbox ids.
    pub mailbox: String,
    /// This computer's id in the server's device registry, which the server stamps on this computer's own asks.
    pub device_id: String,
    pub relay_token: String,
    /// The server's X25519 static key in base64, the one every IK handshake must reach.
    pub runtime_static: String,
    /// This computer's X25519 private key for this server in base64, made for this pairing.
    pub private_key: String,
    pub voice: Option<String>,
    pub speaks: Option<bool>,
    /// Milliseconds since the epoch.
    pub paired_at: u64,
}

/// What the pages are told about a server: no key and no token.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerSummary {
    pub machine_id: String,
    pub machine: String,
    pub device_id: String,
    pub paired_at: u64,
}

impl PairedServer {
    pub fn summary(&self) -> ServerSummary {
        ServerSummary { machine_id: self.machine_id.clone(), machine: self.machine.clone(), device_id: self.device_id.clone(), paired_at: self.paired_at }
    }
}

/// Where the paired servers are kept between launches.
pub trait ServerStore: Send + Sync {
    /// Every server, oldest pairing first.
    fn all(&self) -> Result<Vec<PairedServer>, String>;
    /// Kept beside the others, replacing an earlier pairing with the same machine.
    fn save(&self, server: &PairedServer) -> Result<(), String>;
    fn forget(&self, machine_id: &str) -> Result<(), String>;
}

/// The system's own store: Credential Manager on Windows, the Secret Service on Linux. One entry per server,
/// since Credential Manager caps one secret at 2560 bytes, and one entry listing their ids, since neither lists by service.
pub struct KeyringServers {
    service: String,
}

impl KeyringServers {
    pub const SERVICE: &'static str = "com.memnox.desktop.servers";
    const INDEX: &'static str = "index";

    pub fn new(service: &str) -> Self {
        Self { service: service.to_owned() }
    }

    fn entry(&self, account: &str) -> Result<keyring::Entry, String> {
        keyring::Entry::new(&self.service, account).map_err(|why| why.to_string())
    }

    fn account(machine_id: &str) -> String {
        format!("server:{machine_id}")
    }

    fn ids(&self) -> Result<Vec<String>, String> {
        match self.entry(Self::INDEX)?.get_password() {
            Ok(text) => serde_json::from_str(&text).map_err(|why| why.to_string()),
            Err(keyring::Error::NoEntry) => Ok(Vec::new()),
            Err(why) => Err(why.to_string()),
        }
    }

    fn write_ids(&self, ids: &[String]) -> Result<(), String> {
        let text = serde_json::to_string(ids).map_err(|why| why.to_string())?;
        self.entry(Self::INDEX)?.set_password(&text).map_err(|why| why.to_string())
    }
}

impl ServerStore for KeyringServers {
    fn all(&self) -> Result<Vec<PairedServer>, String> {
        let mut servers = Vec::new();
        for id in self.ids()? {
            match self.entry(&Self::account(&id))?.get_password() {
                Ok(text) => servers.extend(serde_json::from_str::<PairedServer>(&text).ok()),
                // Listed but gone, such as removed by hand in the credential manager, so it is simply not there.
                Err(keyring::Error::NoEntry) => continue,
                Err(why) => return Err(why.to_string()),
            }
        }
        servers.sort_by_key(|server| server.paired_at);
        Ok(servers)
    }

    fn save(&self, server: &PairedServer) -> Result<(), String> {
        let text = serde_json::to_string(server).map_err(|why| why.to_string())?;
        self.entry(&Self::account(&server.machine_id))?.set_password(&text).map_err(|why| why.to_string())?;
        let mut ids = self.ids()?;
        if !ids.contains(&server.machine_id) {
            ids.push(server.machine_id.clone());
            self.write_ids(&ids)?;
        }
        Ok(())
    }

    fn forget(&self, machine_id: &str) -> Result<(), String> {
        match self.entry(&Self::account(machine_id))?.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => {}
            Err(why) => return Err(why.to_string()),
        }
        let ids: Vec<String> = self.ids()?.into_iter().filter(|id| id != machine_id).collect();
        self.write_ids(&ids)
    }
}

/// The servers in memory, for tests.
#[cfg(test)]
#[derive(Default)]
pub struct MemoryServers {
    kept: Mutex<HashMap<String, PairedServer>>,
}

#[cfg(test)]
impl ServerStore for MemoryServers {
    fn all(&self) -> Result<Vec<PairedServer>, String> {
        let mut servers: Vec<PairedServer> = self.kept.lock().map_err(|why| why.to_string())?.values().cloned().collect();
        servers.sort_by_key(|server| server.paired_at);
        Ok(servers)
    }

    fn save(&self, server: &PairedServer) -> Result<(), String> {
        self.kept.lock().map_err(|why| why.to_string())?.insert(server.machine_id.clone(), server.clone());
        Ok(())
    }

    fn forget(&self, machine_id: &str) -> Result<(), String> {
        self.kept.lock().map_err(|why| why.to_string())?.remove(machine_id);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn server(id: &str, at: u64) -> PairedServer {
        PairedServer {
            machine_id: id.into(),
            machine: format!("box {id}"),
            relay_url: "wss://relay.example/v1/relay".into(),
            mailbox: "AAAAAAAAAAAAAAAAAAAAAA".into(),
            device_id: format!("dev_{id}"),
            relay_token: "rly_secret".into(),
            runtime_static: "key".into(),
            private_key: "private".into(),
            voice: None,
            speaks: Some(false),
            paired_at: at,
        }
    }

    #[test]
    fn keeps_one_record_per_machine_oldest_first() {
        let store = MemoryServers::default();
        store.save(&server("b", 20)).unwrap();
        store.save(&server("a", 10)).unwrap();
        store.save(&server("b", 30)).unwrap();
        let ids: Vec<(String, u64)> = store.all().unwrap().into_iter().map(|s| (s.machine_id, s.paired_at)).collect();
        assert_eq!(ids, vec![("a".into(), 10), ("b".into(), 30)]);
        store.forget("a").unwrap();
        assert_eq!(store.all().unwrap().len(), 1);
    }

    #[test]
    fn the_summary_carries_no_secret() {
        let text = serde_json::to_string(&server("a", 1).summary()).unwrap();
        assert!(!text.contains("rly_secret") && !text.contains("private"));
        assert!(text.contains("\"machineId\":\"a\""));
    }
}
