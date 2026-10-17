import nodeProcess from 'node:process'
import { readConfig } from '../config.js'
import { createPool, logDroppedConnections } from '../db/pool.js'
import { pruneShopOutbox } from '../db/pruneShopOutbox.js'
import { describeError, log } from '../log.js'

// Run once a day from cron (README, "Outbox prune job"). Every prune statement stands alone, so one connection is enough.
async function main(): Promise<void> {
  const config = readConfig()
  const pool = createPool(config.databaseUrl, { max: 1 })
  logDroppedConnections(pool, 'prune-outbox')
  try {
    await pruneShopOutbox(pool)
  } finally {
    await pool.end()
  }
}

main().catch((error) => {
  log('prune-outbox', 'failed', { message: describeError(error) })
  nodeProcess.exitCode = 1
})
