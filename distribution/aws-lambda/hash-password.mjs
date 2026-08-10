#!/usr/bin/env node
// Computes the same PBKDF2-SHA256 (100000 iterations, 256-bit) hash index.mjs's
// hashPassword() verifies against, so a record written by add-company-user.sh always
// matches what /auth computes at login time.
import { randomBytes, pbkdf2Sync } from 'node:crypto';

const ITERATIONS = 100000;
const KEY_LENGTH_BYTES = 32;

const password = process.argv[2];
if (!password) {
  console.error('Usage: node hash-password.mjs <password>');
  process.exit(1);
}

const salt = randomBytes(16).toString('hex');
const hash = pbkdf2Sync(password, Buffer.from(salt, 'hex'), ITERATIONS, KEY_LENGTH_BYTES, 'sha256').toString('hex');

console.log(JSON.stringify({ salt, passwordHash: hash }));
