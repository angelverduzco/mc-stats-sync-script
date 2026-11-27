import fs from 'node:fs/promises';
import path from 'node:path';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';

const MC_DIR = process.env.MC_DIR || '/home/ec2-user/minecraft';
const BUCKET_NAME = process.env.S3_BUCKET || 'pilinescraft-bucket';
const REGION = process.env.AWS_REGION || 'us-east-2';

const s3 = new S3Client({ region: REGION });

// Limpia prefijos como "minecraft:diamond_ore" -> "diamond_ore" (conserva namespace si es de un mod)
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
    // Registro dinámico de todas las categorías y métricas que vayan apareciendo
    const catalog = {};

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const uuid = file.replace('.json', '');
      const rawStats = await fs.readFile(path.join(statsDir, file), 'utf-8');
      const parsed = JSON.parse(rawStats);
      const rawCategories = parsed.stats || {};

      const normalizedStats = {};

      // Recorre dinámicamente cada categoría y cada estadística dentro de ella
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
        name: uuidToName[uuid] || 'Desconocido',
        stats: normalizedStats
      });
    }

    // Convertir los Sets del catálogo a Arrays ordenados para el JSON
    const availableStats = Object.fromEntries(
      Object.entries(catalog).map(([cat, set]) => [cat, Array.from(set).sort()])
    );

    const payload = {
      updatedAt: new Date().toISOString(),
      availableStats, // Lista maestra de todas las stats descubiertas hasta hoy
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
    console.log(`[${new Date().toISOString()}] Estadísticas completas subidas correctamente.`);
  } catch (error) {
    console.error('Error sincronizando estadísticas:', error);
    process.exit(1);
  }
}

syncStats();