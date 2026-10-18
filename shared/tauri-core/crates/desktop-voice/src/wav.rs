//! The WAV a system voice hands back, read into mono samples so it plays through the same sink, meter
//! and echo canceller as Kokoro does.

/// Sixteen bit samples run from minus this to just under it.
const PCM16_SCALE: f32 = 32_768.0;
const PCM: u16 = 1;
const FLOAT: u16 = 3;

/// Mono samples and their rate from a RIFF WAV of 16 bit PCM or 32 bit float, channels averaged; None
/// for anything else. A length of zero or past the end, as a stream written to stdout carries, reads to the end.
pub fn wav_samples(bytes: &[u8]) -> Option<(Vec<f32>, u32)> {
    if bytes.len() < 12 || &bytes[0..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
        return None;
    }
    let mut at = 12;
    let mut format: Option<(u16, u16, u32, u16)> = None;
    while at + 8 <= bytes.len() {
        let id = &bytes[at..at + 4];
        let size = u32::from_le_bytes(bytes[at + 4..at + 8].try_into().ok()?) as usize;
        let body = at + 8;
        if id == b"fmt " && body + 16 <= bytes.len() {
            let word =
                |from: usize| u16::from_le_bytes([bytes[body + from], bytes[body + from + 1]]);
            let rate = u32::from_le_bytes(bytes[body + 4..body + 8].try_into().ok()?);
            format = Some((word(0), word(2), rate, word(14)));
        } else if id == b"data" {
            let (kind, channels, rate, bits) = format?;
            let end = if size == 0 || body + size > bytes.len() {
                bytes.len()
            } else {
                body + size
            };
            let data = &bytes[body..end];
            let channels = usize::from(channels.max(1));
            let samples: Vec<f32> = match (kind, bits) {
                (PCM, 16) => data
                    .chunks_exact(2)
                    .map(|pair| f32::from(i16::from_le_bytes([pair[0], pair[1]])) / PCM16_SCALE)
                    .collect(),
                (FLOAT, 32) => data
                    .chunks_exact(4)
                    .map(|four| f32::from_le_bytes([four[0], four[1], four[2], four[3]]))
                    .collect(),
                _ => return None,
            };
            let mono = samples
                .chunks(channels)
                .map(|frame| frame.iter().sum::<f32>() / frame.len() as f32)
                .collect();
            return Some((mono, rate));
        }
        // Chunks are padded to an even length.
        at = body + size + (size & 1);
    }
    None
}

#[cfg(test)]
mod tests {
    use super::wav_samples;

    fn wav(channels: u16, rate: u32, samples: &[i16], data_size: Option<u32>) -> Vec<u8> {
        let mut bytes = b"RIFF\0\0\0\0WAVEfmt ".to_vec();
        bytes.extend(16_u32.to_le_bytes());
        bytes.extend(1_u16.to_le_bytes());
        bytes.extend(channels.to_le_bytes());
        bytes.extend(rate.to_le_bytes());
        bytes.extend((rate * 2 * u32::from(channels)).to_le_bytes());
        bytes.extend((2 * channels).to_le_bytes());
        bytes.extend(16_u16.to_le_bytes());
        bytes.extend(b"data");
        bytes.extend(data_size.unwrap_or(samples.len() as u32 * 2).to_le_bytes());
        for sample in samples {
            bytes.extend(sample.to_le_bytes());
        }
        bytes
    }

    #[test]
    fn reads_sixteen_bit_mono_and_averages_stereo() {
        assert_eq!(
            wav_samples(&wav(1, 22_050, &[16_384, -16_384], None)),
            Some((vec![0.5, -0.5], 22_050))
        );
        assert_eq!(
            wav_samples(&wav(2, 16_000, &[16_384, 0], None)),
            Some((vec![0.25], 16_000))
        );
    }

    #[test]
    fn reads_a_stream_whose_length_was_never_filled_in() {
        assert_eq!(
            wav_samples(&wav(1, 22_050, &[16_384], Some(0x7fff_ffff))),
            Some((vec![0.5], 22_050))
        );
        assert_eq!(wav_samples(b"not a wav"), None);
    }
}
