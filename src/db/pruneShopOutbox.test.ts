import { OUTBOX_PRUNE_FLOOR_MS } from '@kyuworks/sdk'
import type { QueryParam, QueryRows, RelayQueryable } from '@kyuworks/sdk'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { pruneShopOutbox } from './pruneShopOutbox.js'

interface RecordedQuery {
  text: string
  params: readonly QueryParam[]
}

interface LoggedPrune {
  process: string
  event: string
  published: number
  retired: number
  cancelled: number
}

// Fewer rows than one slice for every column, so the SDK sends exactly one DELETE per column.
function deletedRowsFor(text: string): number {
  if (text.includes('published_at <')) return 2
  if (text.includes('dead_at <')) return 1
  return 0
}

function recordingDb(calls: RecordedQuery[]): RelayQueryable {
  return {
    query(text: string, params: readonly QueryParam[]): Promise<QueryRows> {
      calls.push({ text, params })
      return Promise.resolve({ rows: [], rowCount: deletedRowsFor(text) })
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

  it('deletes published, retired and cancelled outbox rows older than the SDK prune floor', async () => {
    vi.spyOn(process.stdout, 'write').mockImplementation(() => true)
    const calls: RecordedQuery[] = []
    const startedAt = Date.now()

    const counts = await pruneShopOutbox(recordingDb(calls))

    const endedAt = Date.now()
    expect(counts).toEqual({ published: 2, retired: 1, cancelled: 0 })
    expect(calls.map((call) => /WHERE (\w+) </.exec(call.text)?.[1])).toEqual([
      'published_at',
      'dead_at',
      'cancelled_at',
    ])
    for (const call of calls) {
      expect(call.text.startsWith('DELETE FROM kyu_outbox')).toBe(true)
      const before = call.params[0]
      if (!(before instanceof Date)) throw new Error(`expected a Date cutoff, got ${String(before)}`)
      expect(before.getTime()).toBeGreaterThanOrEqual(startedAt - OUTBOX_PRUNE_FLOOR_MS)
      expect(before.getTime()).toBeLessThanOrEqual(endedAt - OUTBOX_PRUNE_FLOOR_MS)
      expect(call.params[1]).toBe(1000)
    }
  })

  it('logs what it deleted as one prune-outbox done line', async () => {
    const write = vi.spyOn(process.stdout, 'write').mockImplementation(() => true)

    await pruneShopOutbox(recordingDb([]))

    expect(write).toHaveBeenCalledTimes(1)
    const record: LoggedPrune = JSON.parse(String(write.mock.calls[0]?.[0]))
    expect(record).toMatchObject({ process: 'prune-outbox', event: 'done', published: 2, retired: 1, cancelled: 0 })
  })

  it('rejects with the database error and logs no done line when a delete fails', async () => {
    const write = vi.spyOn(process.stdout, 'write').mockImplementation(() => true)

    await expect(pruneShopOutbox(failingDb())).rejects.toThrow('connection refused')

    expect(write).not.toHaveBeenCalled()
  })
})
