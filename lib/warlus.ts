// lib/walrus.ts
import axios from 'axios';

const PUBLISHER_URL = "https://publisher.walrus-testnet.walrus.space";
const AGGREGATOR_URL = "https://aggregator.walrus-testnet.walrus.space";

export async function uploadToWalrus(file: Blob): Promise<string> {
  // Walrus expects a PUT request with the binary body
  try {
    const response = await axios.put(
      `${PUBLISHER_URL}/v1/store?epochs=5`, // Store for 5 epochs (short time for testnet)
      file, 
      { headers: { 'Content-Type': 'application/octet-stream' } }
    );

    // The response structure usually contains 'newlyCreated' or 'alreadyCertified'
    const blobId = response.data.newlyCreated?.blobObject.blobId || 
                   response.data.alreadyCertified?.blobId;
                   
    if (!blobId) throw new Error("No Blob ID returned from Walrus");
    
    return blobId;
  } catch (err) {
    console.error("Walrus Upload Error:", err);
    throw err;
  }
}

export async function fetchFromWalrus(blobId: string): Promise<string> {
  // Fetch the data back as text (since we uploaded stringified JSON from encryption.ts)


         // (ankit change bolbid to bolb if you want to fetch image also but nahi lagta lagega demo ke liye )
  const response = await axios.get(`${AGGREGATOR_URL}/v1/${blobId}`, {
    responseType: 'text' 
  });
  return response.data;
}