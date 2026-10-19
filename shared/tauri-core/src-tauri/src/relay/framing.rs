//! The relay's framing, ported from the Mac's `RelayFraming`: every binary WebSocket message is a mailbox,
//! a kind and a body, and a JSON line is cut into flagged chunks so each sealed one fits one Noise message.

/// A mailbox id is 16 random bytes.
pub const MAILBOX_LEN: usize = 16;
/// The most the relay forwards in one message, mailbox included.
pub const LARGEST_MESSAGE: usize = 65_552;
/// The most UTF-8 one chunk carries, which keeps a sealed chunk under Noise's 65535 byte message.
pub const LARGEST_CHUNK: usize = 65_000;
/// The flag on the chunk that ends a line.
pub const ENDS_LINE: u8 = 0x00;
/// The flag on a chunk with more of the same line after it.
pub const MORE_FOLLOWS: u8 = 0x01;
/// Many megabytes, far past any answer the daemon sends, and still a bound.
pub const LONGEST_LINE: usize = 16 * 1_024 * 1_024;

/// What the first byte of a payload inside a mailbox says follows, as remote-contract.md numbers them.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FrameKind {
    Handshake = 0x01,
    Transport = 0x02,
    /// The sender drops its session.
    Close = 0x03,
}

impl FrameKind {
    fn from_byte(byte: u8) -> Option<Self> {
        match byte {
            0x01 => Some(Self::Handshake),
            0x02 => Some(Self::Transport),
            0x03 => Some(Self::Close),
            _ => None,
        }
    }
}

/// Why a message could not be made or a chunk could not join a line.
#[derive(Debug, PartialEq, Eq)]
pub enum FramingError {
    /// The mailbox id is not the 16 bytes the relay routes by.
    BadMailbox,
    /// Past the bytes the relay forwards in one message.
    TooLarge(usize),
    EmptyChunk,
    UnknownFlag(u8),
    /// Longer than any line this app takes, so a peer that never ends one cannot fill the memory.
    LineTooLong,
}

impl std::fmt::Display for FramingError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}

/// Mailbox, then kind, then body; the relay reads only the mailbox.
pub fn message(mailbox: &[u8], kind: FrameKind, body: &[u8]) -> Result<Vec<u8>, FramingError> {
    if mailbox.len() != MAILBOX_LEN {
        return Err(FramingError::BadMailbox);
    }
    let mut message = Vec::with_capacity(MAILBOX_LEN + 1 + body.len());
    message.extend_from_slice(mailbox);
    message.push(kind as u8);
    message.extend_from_slice(body);
    if message.len() > LARGEST_MESSAGE {
        return Err(FramingError::TooLarge(message.len()));
    }
    Ok(message)
}

/// The kind and body inside a message for this mailbox, or None for one meant elsewhere, empty, or of a kind nobody sends.
pub fn frame<'a>(message: &'a [u8], mailbox: &[u8]) -> Option<(FrameKind, &'a [u8])> {
    if message.len() <= MAILBOX_LEN || &message[..MAILBOX_LEN] != mailbox {
        return None;
    }
    let kind = FrameKind::from_byte(message[MAILBOX_LEN])?;
    Some((kind, &message[MAILBOX_LEN + 1..]))
}

/// A JSON line cut into transport plaintexts: a flag byte, then up to 65000 bytes of UTF-8.
pub fn chunks(line: &[u8]) -> Vec<Vec<u8>> {
    if line.is_empty() {
        return vec![vec![ENDS_LINE]];
    }
    let pieces: Vec<&[u8]> = line.chunks(LARGEST_CHUNK).collect();
    let last = pieces.len() - 1;
    pieces
        .into_iter()
        .enumerate()
        .map(|(index, piece)| {
            let mut chunk = Vec::with_capacity(piece.len() + 1);
            chunk.push(if index == last {
                ENDS_LINE
            } else {
                MORE_FOLLOWS
            });
            chunk.extend_from_slice(piece);
            chunk
        })
        .collect()
}

/// Joins chunks back into whole lines as they are decrypted.
pub struct LineJoiner {
    pending: Vec<u8>,
    longest: usize,
}

impl Default for LineJoiner {
    fn default() -> Self {
        Self::new(LONGEST_LINE)
    }
}

impl LineJoiner {
    pub fn new(longest: usize) -> Self {
        Self {
            pending: Vec::new(),
            longest,
        }
    }

    /// The whole line once its last chunk arrives, None while more is to come.
    pub fn push(&mut self, plaintext: &[u8]) -> Result<Option<Vec<u8>>, FramingError> {
        let (&flag, rest) = plaintext.split_first().ok_or(FramingError::EmptyChunk)?;
        self.pending.extend_from_slice(rest);
        if self.pending.len() > self.longest {
            self.pending.clear();
            return Err(FramingError::LineTooLong);
        }
        match flag {
            ENDS_LINE => Ok(Some(std::mem::take(&mut self.pending))),
            MORE_FOLLOWS => Ok(None),
            other => {
                self.pending.clear();
                Err(FramingError::UnknownFlag(other))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const MAILBOX: [u8; 16] = [7; 16];

    #[test]
    fn a_message_is_mailbox_then_kind_then_body() {
        let made = message(&MAILBOX, FrameKind::Transport, b"sealed").unwrap();
        assert_eq!(&made[..16], &MAILBOX);
        assert_eq!(made[16], 0x02);
        assert_eq!(
            frame(&made, &MAILBOX),
            Some((FrameKind::Transport, &b"sealed"[..]))
        );
    }

    #[test]
    fn refuses_a_short_mailbox_and_a_message_past_the_relay_limit() {
        assert_eq!(
            message(&[1; 15], FrameKind::Close, b""),
            Err(FramingError::BadMailbox)
        );
        let body = vec![0u8; LARGEST_MESSAGE];
        assert_eq!(
            message(&MAILBOX, FrameKind::Transport, &body),
            Err(FramingError::TooLarge(LARGEST_MESSAGE + 17))
        );
    }

    #[test]
    fn drops_another_mailbox_an_empty_message_and_an_unknown_kind() {
        let other = message(&[9; 16], FrameKind::Handshake, b"x").unwrap();
        assert_eq!(frame(&other, &MAILBOX), None);
        assert_eq!(frame(&MAILBOX, &MAILBOX), None);
        let mut odd = MAILBOX.to_vec();
        odd.push(0x09);
        assert_eq!(frame(&odd, &MAILBOX), None);
    }

    #[test]
    fn a_long_line_goes_in_chunks_and_joins_back_whole() {
        let line: Vec<u8> = (0..150_000u32).map(|n| b'a' + (n % 26) as u8).collect();
        let cut = chunks(&line);
        assert_eq!(cut.len(), 3);
        assert_eq!(cut[0][0], MORE_FOLLOWS);
        assert_eq!(cut[2][0], ENDS_LINE);
        let mut joiner = LineJoiner::default();
        assert_eq!(joiner.push(&cut[0]).unwrap(), None);
        assert_eq!(joiner.push(&cut[1]).unwrap(), None);
        assert_eq!(joiner.push(&cut[2]).unwrap(), Some(line));
    }

    #[test]
    fn an_empty_line_is_one_ending_chunk() {
        assert_eq!(chunks(b""), vec![vec![ENDS_LINE]]);
        assert_eq!(
            LineJoiner::default().push(&[ENDS_LINE]).unwrap(),
            Some(Vec::new())
        );
    }

    #[test]
    fn refuses_an_empty_chunk_an_unknown_flag_and_a_line_too_long() {
        let mut joiner = LineJoiner::new(4);
        assert_eq!(joiner.push(&[]), Err(FramingError::EmptyChunk));
        assert_eq!(joiner.push(&[7, 1]), Err(FramingError::UnknownFlag(7)));
        assert_eq!(
            joiner.push(&[MORE_FOLLOWS, 1, 2, 3, 4, 5]),
            Err(FramingError::LineTooLong)
        );
        assert_eq!(joiner.push(&[ENDS_LINE, 1]).unwrap(), Some(vec![1]));
    }
}
