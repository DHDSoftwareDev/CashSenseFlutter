// Offline checks must never read host credentials or contact any network endpoint.
import net from 'node:net';
import tls from 'node:tls';
import http from 'node:http';
import https from 'node:https';
import {syncBuiltinESMExports} from 'node:module';
process.env.AWS_EC2_METADATA_DISABLED='true';
process.env.AWS_ACCESS_KEY_ID='OFFLINE_TEST_ONLY';
process.env.AWS_SECRET_ACCESS_KEY='OFFLINE_TEST_ONLY';
process.env.AWS_REGION='us-east-1';
const blocked=()=>{throw new Error('Offline verification blocked an unexpected network request');};
net.Socket.prototype.connect=blocked;
net.connect=blocked; net.createConnection=blocked; tls.connect=blocked;
http.request=blocked;http.get=blocked;https.request=blocked;https.get=blocked;
globalThis.fetch=blocked;
syncBuiltinESMExports();
