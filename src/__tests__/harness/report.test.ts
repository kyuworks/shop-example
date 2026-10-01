import { describe, expect, it } from 'vitest'
import { composeImageTag, readCommitSha, readSdkVersion, reportSummaryLines } from './report.js'
import type { HarnessReport } from './report.js'

describe('readCommitSha', () => {
  it('returns KYU_HARNESS_COMMIT_SHA when it is set', () => {
    const original = process.env['KYU_HARNESS_COMMIT_SHA']
    process.env['KYU_HARNESS_COMMIT_SHA'] = 'abc123'
    try {
      expect(readCommitSha()).toBe('abc123')
    } finally {
      if (original === undefined) delete process.env['KYU_HARNESS_COMMIT_SHA']
      else process.env['KYU_HARNESS_COMMIT_SHA'] = original
    }
  })

  it('falls back to git rev-parse HEAD when the env var is unset', () => {
    const original = process.env['KYU_HARNESS_COMMIT_SHA']
    delete process.env['KYU_HARNESS_COMMIT_SHA']
    try {
      expect(readCommitSha()).toMatch(/^[0-9a-f]{40}(-dirty)?$/)
    } finally {
      if (original !== undefined) process.env['KYU_HARNESS_COMMIT_SHA'] = original
    }
  })
})

describe('composeImageTag', () => {
  it('reads the pinned tag from infra/hatchet/compose.yaml when no env override is set', () => {
    const original = process.env['KYU_HATCHET_IMAGE_TAG']
    delete process.env['KYU_HATCHET_IMAGE_TAG']
    try {
      // Keep in step with infra/hatchet/compose.yaml's pinned default.
      expect(composeImageTag()).toBe('hatchet-lite:v0.107.0')
    } finally {
      if (original !== undefined) process.env['KYU_HATCHET_IMAGE_TAG'] = original
    }
  })

  it('prefers the env override over the compose file default', () => {
    const original = process.env['KYU_HATCHET_IMAGE_TAG']
    process.env['KYU_HATCHET_IMAGE_TAG'] = 'v9.9.9'
    try {
      expect(composeImageTag()).toBe('hatchet-lite:v9.9.9')
    } finally {
      if (original === undefined) delete process.env['KYU_HATCHET_IMAGE_TAG']
      else process.env['KYU_HATCHET_IMAGE_TAG'] = original
    }
  })
})

describe('readSdkVersion', () => {
  it('reads the installed @kyuworks/sdk version from node_modules', () => {
    expect(readSdkVersion()).toMatch(/^\d+\.\d+\.\d+/)
  })
})

describe('reportSummaryLines', () => {
  it('names the commit and the SDK version before the scenario lines', () => {
    const report: HarnessReport = {
      commitSha: 'abc123',
      sdkVersion: '0.1.0',
      machine: { platform: 'linux', arch: 'x64', cpuCount: 1, totalMemBytes: 1 },
      engineVersion: 'v0',
      reportBuiltAt: '2026-10-01T00:00:00.000Z',
      scenarios: [],
    }
    expect(reportSummaryLines(report)).toEqual(['commit abc123  @kyuworks/sdk 0.1.0'])
  })
})
