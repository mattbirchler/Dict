// Prints the public key for a private key seed read from stdin.
import { readFileSync } from "node:fs";
import { privateKeyFromSeed, publicKeyBase64 } from "./license.mjs";
console.log(publicKeyBase64(privateKeyFromSeed(readFileSync(0, "utf8"))));
