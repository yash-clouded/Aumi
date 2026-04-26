const WebSocket = require('ws');
const http = require('http');

const PORT = process.env.PORT || 8080;
const server = http.createServer();
const wss = new WebSocket.Server({ server });

// Map to store connected devices
// Map<deviceId, WebSocket>
const clients = new Map();

wss.on('connection', (ws) => {
    let deviceId = null;

    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);

            // 1. Handshake/Register
            if (data.type === 'REGISTER') {
                deviceId = data.deviceId;
                clients.set(deviceId, ws);
                console.log(`Device registered: ${deviceId}`);
                ws.send(JSON.stringify({ type: 'REGISTER_OK' }));
                return;
            }

            // 2. Forwarding
            if (data.targetId && clients.has(data.targetId)) {
                const targetWs = clients.get(data.targetId);
                if (targetWs.readyState === WebSocket.OPEN) {
                    targetWs.send(JSON.stringify({
                        ...data,
                        fromId: deviceId
                    }));
                }
            }
        } catch (e) {
            console.error('Error processing message:', e);
        }
    });

    ws.on('close', () => {
        if (deviceId) {
            clients.delete(deviceId);
            console.log(`Device disconnected: ${deviceId}`);
        }
    });
});

server.listen(PORT, () => {
    console.log(`Aumi Relay Server running on port ${PORT}`);
});
