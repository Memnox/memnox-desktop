//! Memnox's icon in the Linux tray as a StatusNotifierItem, which KDE Plasma shows natively and GNOME
//! shows through the AppIndicator extension. Unlike libayatana appindicator, the item is told of a left
//! click (`Activate`), so the panel opens beside the icon as the Mac's status item opens it, and the
//! menu waits for a right click.

use std::sync::Arc;

use ksni::blocking::{Handle, TrayMethods};
use ksni::menu::{CheckmarkItem, StandardItem};
use ksni::{Category, Icon, MenuItem, ToolTip, Tray};

/// One row of the right click menu.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum StatusRow {
    /// A row that does one thing, told back by its id.
    Press {
        id: String,
        title: String,
    },
    /// A row with a tick, such as starting at sign in; pressing it tells its id back.
    Tick {
        id: String,
        title: String,
    },
    Separator,
}

/// What the person did with the icon.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum StatusPress {
    /// A left click, at the place on screen the tray host gave, which GNOME often leaves at 0, 0.
    Open { x: i32, y: i32 },
    /// A row of the menu, by its id.
    Row(String),
}

type Told = Arc<dyn Fn(StatusPress) + Send + Sync>;

struct Item {
    rows: Vec<StatusRow>,
    ticked: bool,
    icon: Icon,
    told: Told,
}

impl Tray for Item {
    // The left click opens the panel rather than the menu, so the host is told the item is no menu.
    const MENU_ON_ACTIVATE: bool = false;

    fn id(&self) -> String {
        "memnox".into()
    }

    fn title(&self) -> String {
        "Memnox".into()
    }

    fn category(&self) -> Category {
        Category::ApplicationStatus
    }

    fn icon_pixmap(&self) -> Vec<Icon> {
        vec![self.icon.clone()]
    }

    fn tool_tip(&self) -> ToolTip {
        ToolTip {
            title: "Memnox".into(),
            ..Default::default()
        }
    }

    fn activate(&mut self, x: i32, y: i32) {
        (self.told)(StatusPress::Open { x, y });
    }

    fn menu(&self) -> Vec<MenuItem<Self>> {
        self.rows
            .iter()
            .map(|row| match row {
                StatusRow::Press { id, title } => {
                    let id = id.clone();
                    StandardItem {
                        label: title.clone(),
                        activate: Box::new(move |item: &mut Self| {
                            (item.told)(StatusPress::Row(id.clone()))
                        }),
                        ..Default::default()
                    }
                    .into()
                }
                StatusRow::Tick { id, title } => {
                    let id = id.clone();
                    CheckmarkItem {
                        label: title.clone(),
                        checked: self.ticked,
                        activate: Box::new(move |item: &mut Self| {
                            (item.told)(StatusPress::Row(id.clone()))
                        }),
                        ..Default::default()
                    }
                    .into()
                }
                StatusRow::Separator => MenuItem::Separator,
            })
            .collect()
    }
}

/// The icon while it is in the tray; dropping it leaves the icon up for as long as the app runs.
pub struct StatusItem(Handle<Item>);

impl StatusItem {
    /// Puts the icon in the tray, or says why it cannot be shown, such as no tray host on stock GNOME, so
    /// the caller can fall back to another tray. `rgba` is the icon's pixels as RGBA, row by row.
    pub fn start(
        rgba: &[u8],
        width: u32,
        height: u32,
        rows: Vec<StatusRow>,
        ticked: bool,
        told: impl Fn(StatusPress) + Send + Sync + 'static,
    ) -> Result<Self, String> {
        let item = Item {
            rows,
            ticked,
            icon: Icon {
                width: i32::try_from(width).map_err(|error| error.to_string())?,
                height: i32::try_from(height).map_err(|error| error.to_string())?,
                data: argb(rgba),
            },
            told: Arc::new(told),
        };
        item.spawn()
            .map(StatusItem)
            .map_err(|error| error.to_string())
    }

    /// Ticks or clears the one row with a tick, once the change it asked for has been made.
    pub fn set_ticked(&self, on: bool) {
        self.0.update(|item| item.ticked = on);
    }
}

/// RGBA pixels as the ARGB32 in network byte order that the StatusNotifierItem pixmap carries.
fn argb(rgba: &[u8]) -> Vec<u8> {
    rgba.chunks_exact(4)
        .flat_map(|pixel| [pixel[3], pixel[0], pixel[1], pixel[2]])
        .collect()
}

#[cfg(test)]
mod tests {
    use super::argb;

    #[test]
    fn moves_alpha_to_the_front() {
        assert_eq!(
            argb(&[1, 2, 3, 4, 5, 6, 7, 8]),
            vec![4, 1, 2, 3, 8, 5, 6, 7]
        );
    }
}
