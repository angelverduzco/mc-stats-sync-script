import fs from 'node:fs/promises';
import path from 'node:path';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';

const MC_DIR = process.env.MC_DIR || '/home/ec2-user/minecraft';
const BUCKET_NAME = process.env.S3_BUCKET || 'pilinescraft-bucket';
const REGION = process.env.AWS_REGION || 'us-east-2';

const s3 = new S3Client({ region: REGION });

// Strips prefixes like "minecraft:diamond_ore" -> "diamond_ore" (keeps the namespace for modded keys)
function cleanKey(key) {
  return key.startsWith('minecraft:') ? key.replace('minecraft:', '') : key;
}

async function syncStats() {
  try {
    const userCacheRaw = await fs.readFile(path.join(MC_DIR, 'usercache.json'), 'utf-8');
    const userCache = JSON.parse(userCacheRaw);
    const uuidToName = Object.fromEntries(userCache.map(u => [u.uuid, u.name]));

    const statsDir = path.join(MC_DIR, 'world', 'stats');
    const files = await fs.readdir(statsDir);

    const playersData = [];
    // Dynamic registry of every category and metric found along the way
    const catalog = {};

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const uuid = file.replace('.json', '');
      const rawStats = await fs.readFile(path.join(statsDir, file), 'utf-8');
      const parsed = JSON.parse(rawStats);
      const rawCategories = parsed.stats || {};

      const normalizedStats = {};

      // Dynamically walk every category and every stat inside it
      for (const [rawCategory, metrics] of Object.entries(rawCategories)) {
        const category = cleanKey(rawCategory);
        normalizedStats[category] = {};

        if (!catalog[category]) {
          catalog[category] = new Set();
        }

        for (const [rawMetric, value] of Object.entries(metrics)) {
          const metric = cleanKey(rawMetric);
          normalizedStats[category][metric] = value;
          catalog[category].add(metric);
        }
      }

      playersData.push({
        uuid,
        name: uuidToName[uuid] || 'Unknown',
        stats: normalizedStats
      });
    }

    // Convert the catalog Sets to sorted Arrays for the JSON output
    const availableStats = Object.fromEntries(
      Object.entries(catalog).map(([cat, set]) => [cat, Array.from(set).sort()])
    );

    const payload = {
      updatedAt: new Date().toISOString(),
      availableStats, // Master list of every stat discovered so far
      players: playersData
    };

    const command = new PutObjectCommand({
      Bucket: BUCKET_NAME,
      Key: 'stats.json',
      Body: JSON.stringify(payload, null, 2),
      ContentType: 'application/json',
      CacheControl: 'max-age=300'
    });

    await s3.send(command);
    console.log(`[${new Date().toISOString()}] Full stats uploaded successfully.`);
  } catch (error) {
    console.error('Error syncing stats:', error);
    process.exit(1);
  }
}

syncStats();