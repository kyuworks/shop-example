import { spawn } from 'node:child_process'
import path from 'node:path'
import nodeProcess from 'node:process'
import { uuidv7 } from '@kyuworks/sdk'
import { Client } from 'pg'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { readConfig } from '../config.js'

// The built command, run as its own process, the way an operator's cron entry runs it.
const PRUNE_SCRIPT = path.resolve(import.meta.dirname, '../../dist/bin/prune.js')

const PUBLISHED_ROW = `INSERT INTO kyu_outbox (id, name, envelope, created_at, published_at)
  VALUES ($1, 'shop.order.placed', '{"name":"shop.order.placed"}'::jsonb,
          now() - make_interval(days => $2::int), now() - make_interval(days => $2::int))`
const PENDING_ROW = `INSERT INTO kyu_outbox (id, name, envelope, created_at, publish_at)
  VALUES ($1, 'shop.order.placed', '{"name":"shop.order.placed"}'::jsonb,
          now() - make_interval(days => $2::int), now() - make_interval(days => $2::int))`

const oldPublished = uuidv7()
const oldPending = uuidv7()
const recentPublished = uuidv7()
const rowIds = [oldPublished, oldPending, recentPublished]

let admin: Client

beforeAll(async () => {
  admin = new Client({ connectionString: readConfig().databaseUrl })
  await admin.connect()
})

afterAll(async () => {
  await admin.query('DELETE FROM kyu_outbox WHERE id = ANY($1::uuid[])', [rowIds])
  await admin.end()
})

interface CommandResult {
  code: number
  stdout: string
}

function runPruneCommand(env: NodeJS.ProcessEnv): Promise<CommandResult> {
  return new Promise<CommandResult>((resolve, reject) => {
    const child = spawn(nodeProcess.execPath, [PRUNE_SCRIPT], { env, stdio: ['ignore', 'pipe', 'inherit'] })
    let stdout = ''
    child.stdout.on('data', (chunk: Buffer) => {
      stdout += chunk.toString('utf8')
    })
    child.once('error', reject)
    child.once('close', (code) => resolve({ code: code ?? -1, stdout }))
  })
}

interface PruneCounts {
  published: number
  retired: number
  cancelled: number
}

function readDoneCounts(stdout: string): PruneCounts {
  const line = stdout.split('\n').find((candidate) => candidate.includes('"event":"done"'))
  if (line === undefined) throw new Error(`the command printed no done line. stdout: ${stdout}`)
  const record: PruneCounts = JSON.parse(line)
  return record
}

describe('the prune-outbox command', () => {
  it('deletes a row published 50 days ago and keeps a pending row of the same age and a recent published row', async () => {
    await admin.query(PUBLISHED_ROW, [oldPublished, 50])
    await admin.query(PENDING_ROW, [oldPending, 50])
    await admin.query(PUBLISHED_ROW, [recentPublished, 1])

    const result = await runPruneCommand({ ...nodeProcess.env })

    expect(result.stdout).not.toContain('"event":"failed"')
    expect(result.code).toBe(0)
    expect(readDoneCounts(result.stdout)).toEqual(expect.objectContaining({ published: 1, retired: 0, cancelled: 0 }))
    const left = await admin.query<{ id: string }>('SELECT id FROM kyu_outbox WHERE id = ANY($1::uuid[])', [rowIds])
    expect(new Set(left.rows.map((row) => row.id))).toEqual(new Set([oldPending, recentPublished]))
  })

  it('exits 1 and prints a failed line when the database does not exist', async () => {
    const missing = new URL(readConfig().databaseUrl)
    missing.pathname = '/kyu_shop_prune_missing'

    const result = await runPruneCommand({ ...nodeProcess.env, KYU_SHOP_DATABASE_URL: missing.toString() })

    expect(result.code).toBe(1)
    expect(result.stdout).toContain('"process":"prune-outbox","event":"failed"')
  })
})
