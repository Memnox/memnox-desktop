// No console window behind the island in a release build on Windows.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    memnox_desktop_lib::run()
}
