import WebSocket, { WebSocketServer } from 'ws';
import http from 'http';

/**
 * Aumi Relay Server
 * Handles device registration and E2EE message routing between paired clients.
 */

const port = process.env.PORT || 443;
const server = http.createServer();
const wss = new WebSocketServer({ server });

// Map of deviceId -> WebSocket connection
const clients = new Map<string, WebSocket>();

wss.on('connection', (ws: WebSocket) => {
    let deviceId: string | null = null;

    ws.on('message', (data: string) => {
        try {
            const message = JSON.parse(data);
            
            // 1. Handle Registration
            if (message.type === 'REGISTER') {
                deviceId = message.deviceId;
                if (deviceId) {
                    clients.set(deviceId, ws);
                    console.log(`Relay: Registered ${deviceId}`);
                }
            }
            
            // 2. Handle Routing
            if (message.target && clients.has(message.target)) {
                const targetWs = clients.get(message.target);
                if (targetWs && targetWs.readyState === WebSocket.OPEN) {
                    targetWs.send(JSON.stringify(message));
                }
            }
        } catch (e) {
            console.error('Relay Error:', e);
        }
    });

    ws.on('close', () => {
        if (deviceId) {
            clients.delete(deviceId);
            console.log(`Relay: Unregistered ${deviceId}`);
        }
    });
});

server.listen(port, () => {
    console.log(`Aumi Relay listening on port ${port}`);
});
