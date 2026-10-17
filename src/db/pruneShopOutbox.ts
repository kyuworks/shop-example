import { pruneOutbox } from '@kyuworks/sdk'
import type { OutboxPruneCounts, RelayQueryable } from '@kyuworks/sdk'
import { log } from '../log.js'

// The SDK's defaults fit the shop: its longest durable wait is the 1h executionTimeout, and a
// workflow hand-off is a pending outbox row, which the prune never deletes.
export async function pruneShopOutbox(db: RelayQueryable): Promise<OutboxPruneCounts> {
  const counts = await pruneOutbox(db)
  log('prune-outbox', 'done', { published: counts.published, retired: counts.retired, cancelled: counts.cancelled })
  return counts
}
