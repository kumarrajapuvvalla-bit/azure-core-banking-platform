/**
 * Unit tests for complianceRules.ts
 *
 * Tests the tag validation logic in full isolation — no Azure SDK calls.
 * Run with: npm test
 */

import {
  validateResourceTags,
  getNonCompliant,
  complianceRate,
  REQUIRED_TAGS,
  ComplianceResult,
} from './complianceRules';
import { GenericResource } from '@azure/arm-resources';

// ── Helpers ────────────────────────────────────────────────────────────

function makeResource(
  tags: Record<string, string> = {},
  overrides: Partial<GenericResource> = {}
): GenericResource {
  return {
    id: '/subscriptions/sub-1/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sa1',
    name: 'sa1',
    type: 'Microsoft.Storage/storageAccounts',
    tags,
    ...overrides,
  };
}

const FULLY_COMPLIANT_TAGS: Record<string, string> = {
  environment: 'prod',
  owner: 'platform-team',
  'cost-centre': 'CC-1234',
  'data-classification': 'confidential',
};

// ── validateResourceTags ───────────────────────────────────────────────

describe('validateResourceTags', () => {
  it('returns compliant=true when all required tags are present and valid', () => {
    const result = validateResourceTags(makeResource(FULLY_COMPLIANT_TAGS));
    expect(result.compliant).toBe(true);
    expect(result.missingTags).toHaveLength(0);
    expect(result.invalidTags).toHaveLength(0);
  });

  it('flags all required tags as missing when resource has no tags', () => {
    const result = validateResourceTags(makeResource({}));
    expect(result.compliant).toBe(false);
    expect(result.missingTags).toEqual(expect.arrayContaining([...REQUIRED_TAGS]));
  });

  it('flags only the missing tag when one tag is absent', () => {
    const tags = { ...FULLY_COMPLIANT_TAGS };
    delete (tags as Record<string, string>)['cost-centre'];
    const result = validateResourceTags(makeResource(tags));
    expect(result.compliant).toBe(false);
    expect(result.missingTags).toContain('cost-centre');
    expect(result.missingTags).toHaveLength(1);
  });

  it('flags invalid environment value', () => {
    const result = validateResourceTags(
      makeResource({ ...FULLY_COMPLIANT_TAGS, environment: 'staging-broken' })
    );
    expect(result.compliant).toBe(false);
    expect(result.invalidTags).toHaveLength(1);
    expect(result.invalidTags[0].tag).toBe('environment');
  });

  it('flags invalid data-classification value', () => {
    const result = validateResourceTags(
      makeResource({ ...FULLY_COMPLIANT_TAGS, 'data-classification': 'top-secret' })
    );
    expect(result.compliant).toBe(false);
    expect(result.invalidTags[0].tag).toBe('data-classification');
  });

  it('accepts all valid environment values', () => {
    for (const env of ['dev', 'staging', 'prod']) {
      const result = validateResourceTags(
        makeResource({ ...FULLY_COMPLIANT_TAGS, environment: env })
      );
      expect(result.compliant).toBe(true);
    }
  });

  it('treats empty string tag value as missing', () => {
    const result = validateResourceTags(
      makeResource({ ...FULLY_COMPLIANT_TAGS, owner: '   ' })
    );
    expect(result.compliant).toBe(false);
    expect(result.missingTags).toContain('owner');
  });

  it('populates presentTags with only required tag keys', () => {
    const result = validateResourceTags(
      makeResource({ ...FULLY_COMPLIANT_TAGS, 'extra-tag': 'ignored' })
    );
    expect(Object.keys(result.presentTags)).not.toContain('extra-tag');
    expect(Object.keys(result.presentTags)).toHaveLength(REQUIRED_TAGS.length);
  });

  it('handles resource with null tags gracefully', () => {
    const result = validateResourceTags(makeResource(undefined as unknown as Record<string, string>));
    expect(result.compliant).toBe(false);
    expect(result.missingTags).toHaveLength(REQUIRED_TAGS.length);
  });

  it('is case-insensitive for validated tag values', () => {
    const result = validateResourceTags(
      makeResource({ ...FULLY_COMPLIANT_TAGS, environment: 'PROD' })
    );
    expect(result.compliant).toBe(true);
  });
});

// ── getNonCompliant ────────────────────────────────────────────────────────

describe('getNonCompliant', () => {
  it('returns only non-compliant results', () => {
    const results: ComplianceResult[] = [
      { ...validateResourceTags(makeResource(FULLY_COMPLIANT_TAGS)) },
      { ...validateResourceTags(makeResource({})) },
    ];
    const nonCompliant = getNonCompliant(results);
    expect(nonCompliant).toHaveLength(1);
    expect(nonCompliant[0].compliant).toBe(false);
  });

  it('returns empty array when all resources are compliant', () => {
    const results = [validateResourceTags(makeResource(FULLY_COMPLIANT_TAGS))];
    expect(getNonCompliant(results)).toHaveLength(0);
  });
});

// ── complianceRate ─────────────────────────────────────────────────────────

describe('complianceRate', () => {
  it('returns 100% when all resources are compliant', () => {
    const results = [validateResourceTags(makeResource(FULLY_COMPLIANT_TAGS))];
    expect(complianceRate(results)).toBe('100.0%');
  });

  it('returns 0% on empty array', () => {
    expect(complianceRate([])).toBe('0%');
  });

  it('returns 50% when half are compliant', () => {
    const results = [
      validateResourceTags(makeResource(FULLY_COMPLIANT_TAGS)),
      validateResourceTags(makeResource({})),
    ];
    expect(complianceRate(results)).toBe('50.0%');
  });
});
