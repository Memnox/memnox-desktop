// The runtime's own Noise addon as the server's end of an IK session, for the cross check in tunnel.rs.
// It reads hex lines on stdin and writes hex lines on stdout: its static key first, then the handshake
// reply, then each JSON line it opened sealed back to the sender with "seen" added, rekeying every 2 messages.
const readline = require('node:readline');
const noise = require(process.argv[2]);
const keys = noise.generateKeypair();
const mailbox = Buffer.alloc(16, 6);
const out = (bytes) => process.stdout.write(bytes.toString('hex') + '\n');
out(keys.publicKey);
const handshake = noise.Handshake.responder('IK', keys.privateKey);
let transport = null;
let sent = 0;
let received = 0;
readline.createInterface({ input: process.stdin }).on('line', (line) => {
  const message = Buffer.from(line.trim(), 'hex');
  if (!message.subarray(0, 16).equals(mailbox)) throw new Error('another mailbox');
  const kind = message[16];
  const body = message.subarray(17);
  if (transport === null) {
    if (kind !== 1) throw new Error('expected a handshake frame');
    handshake.readMessage(body);
    out(Buffer.concat([mailbox, Buffer.from([1]), handshake.writeMessage(Buffer.alloc(0))]));
    transport = handshake.intoTransport();
    return;
  }
  if (kind !== 2) throw new Error('expected a transport frame');
  const chunk = transport.decrypt(body);
  if ((received += 1) % 2 === 0) transport.rekeyIncoming();
  if (chunk[0] !== 0) throw new Error('expected a whole line');
  const request = JSON.parse(chunk.subarray(1).toString('utf8'));
  const reply = Buffer.concat([Buffer.from([0]), Buffer.from(JSON.stringify({ ...request, seen: true }))]);
  out(Buffer.concat([mailbox, Buffer.from([2]), transport.encrypt(reply)]));
  if ((sent += 1) % 2 === 0) transport.rekeyOutgoing();
});
