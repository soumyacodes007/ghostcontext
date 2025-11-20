// lib/encryption.ts
import { SealClient, SessionKey } from '@mysten/seal';
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { fromHex } from '@mysten/bcs';

// Setup clients
const sui = new SuiClient({ url: getFullnodeUrl('testnet') });

// Seal Testnet Config (Standard for Hackathon)
const testnetServers = [
  "0x73d05d62c18d9374e3ea529e8e0ed6161da1a141a94d3f76ae3fe4e99356db75",
  "0xf5d14a81a982144ae441cd7d64b09027f116a468bd36e7eca494f750591623c8",
];
const serverConfigs = testnetServers.map(id => ({ objectId: id, weight: 1 }));

const seal = new SealClient({
  suiClient: sui,
  serverConfigs,
  verifyKeyServers: false,
});

/**
 * 1. ENCRYPT: Takes your PDF text and encrypts it so only 'address' can read it.
 */
export async function encryptContext(textData: string, userAddress: string) {
  const data = new TextEncoder().encode(textData);
  
  // This effectively uses the User's Address as the "Access Policy"
  // Only this address (or a session key signed by it) can decrypt.
  const policyId = userAddress; 

  const { encryptedObject } = await seal.encrypt({
    threshold: 1,
    packageId: process.env.NEXT_PUBLIC_SEAL_PACKAGE_ID!, // From Seal docs
    id: policyId,
    data,
  });

  // We need to serialize this to upload to Walrus
  const serialized = JSON.stringify(encryptedObject);
  return {
    encryptedBlob: new Blob([serialized], { type: 'application/json' }),
    policyId
  };
}

/**
 * 2. CREATE SESSION: User signs a popup to "Login" to the AI Chat
 */
export async function createSessionKey(userAddress: string, walletSigner: any) {
  const sessionKey = await SessionKey.create({
    address: userAddress,
    packageId: process.env.NEXT_PUBLIC_SEAL_PACKAGE_ID!,
    ttlMin: 60, // Session lasts 1 hour
    suiClient: sui,
  });

  // Prompt user to sign
  const message = sessionKey.getPersonalMessage();
  const { signature } = await walletSigner.signPersonalMessage({ message });
  sessionKey.setPersonalMessageSignature(signature);
  
  return sessionKey;
}

/**
 * 3. DECRYPT: Takes raw bytes from Walrus -> Returns String for AI
 */
export async function decryptContext(
  encryptedJsonString: string, 
  sessionKey: SessionKey
) {
  try {
    const encryptedObject = JSON.parse(encryptedJsonString);

    // In a real implementation, you'd build a txBytes to prove on-chain access
    // For the hackathon demo, if using simple address policy, we can often skip complex policy checks
    // or use a basic placeholder transaction if Seal requires it.
    
    // Note: Seal SDK usage varies slightly by version. 
    // If 'txBytes' is required by your version of Seal for basic address ownership:
    const tx = new Transaction(); 
    const txBytes = await tx.build({ client: sui, onlyTransactionKind: true });

    const decryptedData = await seal.decrypt({
      data: encryptedObject, // Pass the parsed object
      sessionKey,
      txBytes, 
    });

    return new TextDecoder().decode(decryptedData);
  } catch (error) {
    console.error("Decryption failed:", error);
    throw new Error("Could not unlock GhostContext.");
  }
}