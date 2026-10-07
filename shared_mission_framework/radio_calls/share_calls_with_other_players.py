"""Shares the host's radio calls with the other players' radio players, over ZeroTier.

Used by the radio helper (speak_mission_calls.py) on the PC that hosts the mission
(roadmap.md item 19). Another player's PC runs only the radio player, started with
--host <the host's ZeroTier address>: it connects out to here (so it needs no firewall
rule; outgoing connections are allowed) and gets every call the helper voices, the same
header and WAV the host's own radio player gets. Each radio player plays only what its own
jet is tuned to.

It listens on the host's ZeroTier address only (found by itself from the network adapter
whose description says ZeroTier, looked for again every FIND_ADDRESS_EVERY_S until there is
one), so only members of the host's ZeroTier network can reach it. The first time it
listens, Windows asks once whether Python may accept connections: allow it.

On each connection:
    the radio player says   {"hello": "radio player", "computer": "...", "protocol": 1}\\n
    this answers            {"hello": "radio helper", "protocol": 1}\\n
then calls, each as the local radio player gets them (a JSON header line, then its WAV
bytes), and a heartbeat line ({"heartbeat": true}) when nothing was sent for HEARTBEAT_S,
so either side notices a connection that died without closing. A radio player of another
protocol is told so and dropped (its folder is older or newer than the host's).

Each connection is fed by a thread of its own from its own queue, so a slow or lost
connection never holds up the helper or the host's own radio. Its calls' age (age_s) is
worked out the moment each is sent, as the PCs' clocks differ.
"""

import json
import queue
import socket
import subprocess
import threading
import time

import send_radio_call

PORT = 47113
PROTOCOL = 1
FIND_ADDRESS_EVERY_S = 30
HEARTBEAT_S = 15
HELLO_WAIT_S = 10
SEND_TIMEOUT_S = 20
MAX_WAITING_CALLS = 50          # a connection this far behind loses its oldest calls


def zerotier_address():
    """The IPv4 address of this PC's ZeroTier network adapter, or None."""
    command = ("Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ZeroTier*' } | "
               "Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | "
               "Select-Object -ExpandProperty IPAddress")
    try:
        out = subprocess.run(["powershell", "-NoProfile", "-Command", command], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, universal_newlines=True, timeout=20,
                             creationflags=0x08000000).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    addresses = [line.strip() for line in out.splitlines() if line.strip() and not line.startswith("169.254.")]
    return addresses[0] if addresses else None


class OtherPlayers:
    """The other players' radio players connected to this helper."""

    def __init__(self, log, address=None):
        self.log = log
        self.address = address        # given (a test), else ZeroTier's, found by itself
        self.connections = []         # Connection
        self.lock = threading.Lock()
        self.server = None
        self.closed = False
        threading.Thread(target=self.listen, daemon=True).start()

    def listen(self):
        said_looking = False
        while not self.closed:
            address = self.address or zerotier_address()
            if not address:
                if not said_looking:
                    said_looking = True
                    self.log("other players: no ZeroTier address on this PC yet: looking again every %d s "
                             "(calls play on this PC only until then)" % FIND_ADDRESS_EVERY_S)
                time.sleep(FIND_ADDRESS_EVERY_S)
                continue
            try:
                server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                server.bind((address, PORT))
                server.listen(8)
            except OSError as error:
                self.log("other players: can't listen on %s:%d (%s): trying again in %d s"
                         % (address, PORT, error, FIND_ADDRESS_EVERY_S))
                time.sleep(FIND_ADDRESS_EVERY_S)
                continue
            self.server = server
            self.log("other players: their radio players can connect to %s:%d" % (address, PORT))
            while not self.closed:
                try:
                    connection, peer = server.accept()
                except OSError:
                    break
                threading.Thread(target=self.serve, args=(connection, peer[0]), daemon=True).start()
            return

    def serve(self, connection, peer):
        """One radio player's connection: the greeting, then its calls until it goes."""
        name = peer
        try:
            connection.settimeout(HELLO_WAIT_S)
            stream = connection.makefile("rb")
            hello = json.loads(stream.readline().decode("utf-8") or "null")
            if not isinstance(hello, dict) or hello.get("hello") != "radio player":
                self.log("other players: %s connected but isn't a radio player: closed" % peer)
                connection.close()
                return
            name = "%s (%s)" % (hello.get("computer") or "?", peer)
            connection.sendall((json.dumps({"hello": "radio helper", "protocol": PROTOCOL}) + "\n").encode("utf-8"))
            if hello.get("protocol") != PROTOCOL:
                self.log("other players: the radio player on %s is another version (protocol %s, this one %d): "
                         "its radio_calls folder needs updating; closed" % (name, hello.get("protocol"), PROTOCOL))
                connection.close()
                return
        except (OSError, ValueError) as error:
            self.log("other players: %s didn't say hello (%s): closed" % (name, error))
            connection.close()
            return
        connection.settimeout(SEND_TIMEOUT_S)
        player = Connection(connection, name)
        with self.lock:
            self.connections.append(player)
            count = len(self.connections)
        self.log("other players: the radio player on %s connected (%d connected)" % (name, count))
        why = player.run()
        with self.lock:
            if player in self.connections:
                self.connections.remove(player)
            count = len(self.connections)
        self.log("other players: the radio player on %s disconnected: %s (%d connected)" % (name, why, count))

    def send(self, wav, speaker, frequency, read_at, fields):
        """A voiced call to every connected radio player."""
        with self.lock:
            players = list(self.connections)
        for player in players:
            player.add((wav, speaker, frequency, read_at, dict(fields)))
        return len(players)

    def close(self):
        self.closed = True
        if self.server:
            try:
                self.server.close()
            except OSError:
                pass
        with self.lock:
            players = list(self.connections)
        for player in players:
            player.add(None)


class Connection:
    """One connected radio player, fed from its own queue."""

    def __init__(self, connection, name):
        self.connection = connection
        self.name = name
        self.calls = queue.Queue()

    def add(self, call):
        if call is not None and self.calls.qsize() >= MAX_WAITING_CALLS:
            try:
                self.calls.get_nowait()
            except queue.Empty:
                pass
        self.calls.put(call)

    def run(self):
        """Sends until the connection fails or the helper closes; returns why it ended."""
        try:
            while True:
                try:
                    call = self.calls.get(timeout=HEARTBEAT_S)
                except queue.Empty:
                    self.connection.sendall(b'{"heartbeat": true}\n')
                    continue
                if call is None:
                    return "the radio helper closed"
                wav, speaker, frequency, read_at, fields = call
                fields["age_s"] = round(time.time() - read_at, 2)
                self.connection.sendall(send_radio_call.call_bytes(wav, speaker, frequency, **fields))
        except OSError as error:
            return str(error) or error.__class__.__name__
        finally:
            try:
                self.connection.close()
            except OSError:
                pass
