// The written proof this harness exists to produce: one JSON file per run,
// plus a one-line PASS/FAIL per scenario on stdout. Not read by any other
// part of the shop.
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { z } from 'zod'
import type { ScenarioResult } from './scenario.js'

const CI_WORKFLOW_PATH = path.join(path.dirname(fileURLToPath(import.meta.url)), '../../../.github/workflows/ci.yml')
const SDK_PACKAGE_JSON_PATH = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../../node_modules/@kyuworks/sdk/package.json',
)

export interface MachineInfo {
  platform: string
  arch: string
  cpuCount: number
  totalMemBytes: number
}

export interface HarnessReport {
  commitSha: string
  sdkVersion: string
  machine: MachineInfo
  engineVersion: string
  /** When this report was assembled, after every scenario finished — not when the run started. */
  reportBuiltAt: string
  scenarios: readonly ScenarioResult[]
}

// A separate try/catch from the sha read itself: if `git status` fails for
// some reason, that should not turn a good sha read into 'unknown'.
function isWorkingTreeDirty(): boolean {
  try {
    return execFileSync('git', ['status', '--porcelain'], { encoding: 'utf8' }).trim().length > 0
  } catch {
    return false
  }
}

// A build with no .git (a checkout with no .git) stamps the commit in KYU_HARNESS_COMMIT_SHA instead
// of relying on the git read below.
export function readCommitSha(): string {
  const fromEnv = process.env['KYU_HARNESS_COMMIT_SHA']
  if (fromEnv !== undefined && fromEnv !== '') return fromEnv
  try {
    const sha = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim()
    return isWorkingTreeDirty() ? `${sha}-dirty` : sha
  } catch {
    return 'unknown'
  }
}

function readMachineInfo(): MachineInfo {
  return { platform: os.platform(), arch: os.arch(), cpuCount: os.cpus().length, totalMemBytes: os.totalmem() }
}

// ci.yml's hatchet-lite service pins the engine tag; the daily run checks it against kyu's
// compose file (scripts/check-engine-image-tag.sh). Read that pin instead of falling back to 'latest'.
function pinnedEngineDefaultTag(): string {
  const text = fs.readFileSync(CI_WORKFLOW_PATH, 'utf8')
  const match = /ghcr\.io\/hatchet-dev\/hatchet\/hatchet-lite:([^\s'"]+)/.exec(text)
  if (match?.[1] === undefined) throw new Error(`no hatchet-lite image tag found in ${CI_WORKFLOW_PATH}`)
  return match[1]
}

// hatchet-lite has no explicit /api/v1/meta version field today (checked
// against the local engine); this names the pinned tag instead of
// guessing at a field that is not there.
export function pinnedEngineImageTag(): string {
  return `hatchet-lite:${process.env['KYU_HATCHET_IMAGE_TAG'] ?? pinnedEngineDefaultTag()}`
}

const metaResponseSchema = z.object({ version: z.string().optional() })

async function readEngineVersion(): Promise<string> {
  const apiUrl = process.env['HATCHET_CLIENT_API_URL'] ?? 'http://localhost:8888'
  const token = process.env['HATCHET_CLIENT_TOKEN']
  try {
    const headers: Record<string, string> = token !== undefined ? { authorization: `Bearer ${token}` } : {}
    const response = await fetch(`${apiUrl}/api/v1/meta`, { headers })
    if (!response.ok) return pinnedEngineImageTag()
    const parsed = metaResponseSchema.safeParse(await response.json())
    return parsed.success && parsed.data.version !== undefined ? parsed.data.version : pinnedEngineImageTag()
  } catch {
    return pinnedEngineImageTag()
  }
}

const sdkPackageJsonSchema = z.object({ version: z.string() })

// The SDK comes from npm, so the report names the version that ran.
export function readSdkVersion(): string {
  try {
    const parsed = sdkPackageJsonSchema.safeParse(JSON.parse(fs.readFileSync(SDK_PACKAGE_JSON_PATH, 'utf8')))
    return parsed.success ? parsed.data.version : 'unknown'
  } catch {
    return 'unknown'
  }
}

export async function buildReport(scenarios: readonly ScenarioResult[]): Promise<HarnessReport> {
  return {
    commitSha: readCommitSha(),
    sdkVersion: readSdkVersion(),
    machine: readMachineInfo(),
    engineVersion: await readEngineVersion(),
    reportBuiltAt: new Date().toISOString(),
    scenarios,
  }
}

/** The commit and SDK version, then one PASS/FAIL line per scenario, in run order. */
export function reportSummaryLines(report: HarnessReport): readonly string[] {
  return [
    `commit ${report.commitSha}  @kyuworks/sdk ${report.sdkVersion}`,
    ...report.scenarios.map((result) => {
      const status = result.passed ? 'PASS' : 'FAIL'
      const detail = result.passed
        ? `${String(result.durationMs)}ms`
        : (result.error ?? result.failures.map((failure) => `${failure.check}: ${failure.detail}`).join('; '))
      return `${status}  ${result.name}  ${detail}`
    }),
  ]
}
