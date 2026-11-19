import fs from 'node:fs/promises';
import path from 'node:path';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';

// Configuración mediante variables de entorno con valores por defecto
const MC_DIR = process.env.MC_DIR || '/home/ec2-user/minecraft';
const BUCKET_NAME = process.env.S3_BUCKET || 'mi-minecraft-stats-bucket';
const REGION = process.env.AWS_REGION || 'us-east-2';

const s3 = new S3Client({ region: REGION });

async function syncStats() {
  try {
    // 1. Leer usercache.json para mapear UUID -> Nombre de jugador
    const userCacheRaw = await fs.readFile(path.join(MC_DIR, 'usercache.json'), 'utf-8');
    const userCache = JSON.parse(userCacheRaw);
    const uuidToName = Object.fromEntries(userCache.map(u => [u.uuid, u.name]));

    // 2. Leer todos los archivos JSON en world/stats
    const statsDir = path.join(MC_DIR, 'world', 'stats');
    const files = await fs.readdir(statsDir);

    const playersData = [];

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const uuid = file.replace('.json', '');
      const rawStats = await fs.readFile(path.join(statsDir, file), 'utf-8');
      const parsed = JSON.parse(rawStats);
      const custom = parsed.stats?.['minecraft:custom'] || {};

      playersData.push({
        uuid,
        name: uuidToName[uuid] || 'Desconocido',
        playTimeTicks: custom['minecraft:play_time'] || 0,
        deaths: custom['minecraft:deaths'] || 0,
        mobKills: custom['minecraft:mob_kills'] || 0,
        jumps: custom['minecraft:jump'] || 0
      });
    }

    const payload = {
      updatedAt: new Date().toISOString(),
      players: playersData
    };

    // 3. Subir el JSON consolidado a S3
    const command = new PutObjectCommand({
      Bucket: BUCKET_NAME,
      Key: 'stats.json',
      Body: JSON.stringify(payload, null, 2),
      ContentType: 'application/json',
      CacheControl: 'max-age=300' // Evita lecturas excesivas si lo consumes desde una web
    });

    await s3.send(command);
    console.log(`[${new Date().toISOString()}] Estadísticas subidas correctamente.`);
  } catch (error) {
    console.error('Error sincronizando estadísticas:', error);
    process.exit(1);
  }
}

syncStats();