//! When the session rekeys or starts over, ported from the Mac's `NoiseSchedule`. snow does the rekeying;
//! this only counts.

use std::time::Duration;

/// Every 2^20 transport messages in one direction, as remote-contract.md sets for both ends.
pub const REKEY_INTERVAL: u64 = 1 << 20;
/// An hour, after which the link closes and runs a fresh IK handshake, so no session key lives long.
pub const SESSION_LIFETIME: Duration = Duration::from_secs(3_600);

/// Counts messages one way and says when the count reaches the rekey interval.
pub struct RekeyCounter {
    interval: u64,
    count: u64,
}

impl RekeyCounter {
    pub fn new(interval: u64) -> Self {
        Self { interval: interval.max(1), count: 0 }
    }

    /// Counts one message, true when that one completes an interval and the key should turn now.
    pub fn counted(&mut self) -> bool {
        self.count += 1;
        if self.count < self.interval {
            return false;
        }
        self.count = 0;
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn turns_the_key_on_every_interval_and_starts_counting_again() {
        let mut counter = RekeyCounter::new(3);
        assert_eq!([counter.counted(), counter.counted(), counter.counted(), counter.counted()], [false, false, true, false]);
    }

    #[test]
    fn never_counts_to_zero() {
        assert!(RekeyCounter::new(0).counted());
    }
}
