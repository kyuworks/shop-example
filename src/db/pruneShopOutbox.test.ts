import type { QueryRows, RelayQueryable } from '@kyuworks/sdk'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { pruneShopOutbox } from './pruneShopOutbox.js'

interface LoggedPrune {
  process: string
  event: string
  published: number
  retired: number
  cancelled: number
}

// Answers each call with the next scripted row count, so the counts the SDK returns are known
// without reading its SQL. Fewer rows than one slice, so the SDK sends one call per column.
function scriptedDb(rowCounts: readonly number[], calls: { count: number }): RelayQueryable {
  return {
    query(): Promise<QueryRows> {
      const rowCount = rowCounts[calls.count] ?? 0
      calls.count += 1
      return Promise.resolve({ rows: [], rowCount })
    },
  }
}

function failingDb(): RelayQueryable {
  return {
    query(): Promise<QueryRows> {
      return Promise.reject(new Error('connection refused'))
    },
  }
}

describe('pruneShopOutbox', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('runs the SDK prune against the database and returns the counts it computed', async () => {
    vi.spyOn(process.stdout, 'write').mockImplementation(() => true)
    const calls = { count: 0 }

    const counts = await pruneShopOutbox(scriptedDb([2, 1, 3], calls))

    expect(calls.count).toBeGreaterThanOrEqual(1)
    expect(counts).toEqual({ published: 2, retired: 1, cancelled: 3 })
  })

  it('logs the returned counts as one prune-outbox done line', async () => {
    const write = vi.spyOn(process.stdout, 'write').mockImplementation(() => true)

    const counts = await pruneShopOutbox(scriptedDb([2, 1, 3], { count: 0 }))

    expect(write).toHaveBeenCalledTimes(1)
    const record: LoggedPrune = JSON.parse(String(write.mock.calls[0]?.[0]))
    expect(record).toMatchObject({
      process: 'prune-outbox',
      event: 'done',
      published: counts.published,
      retired: counts.retired,
      cancelled: counts.cancelled,
    })
  })

  it('rejects with the database error and logs no done line when a delete fails', async () => {
    const write = vi.spyOn(process.stdout, 'write').mockImplementation(() => true)

    await expect(pruneShopOutbox(failingDb())).rejects.toThrow('connection refused')

    expect(write).not.toHaveBeenCalled()
  })
})
