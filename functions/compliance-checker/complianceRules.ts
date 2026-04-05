/**
 * complianceRules.ts
 *
 * Defines the mandatory FCA compliance tags and the validation logic
 * applied to each Azure resource. Kept separate from the Function handler
 * so it can be unit tested in isolation.
 */

import { GenericResource } from '@azure/arm-resources';

/**
 * Tags that MUST be present on every Azure resource to satisfy
 * FCA SYSC 8.1 audit trail requirements.
 */
export const REQUIRED_TAGS = [
  'environment',       // dev | staging | prod
  'owner',             // team slug or email
  'cost-centre',       // finance chargeback code
  'data-classification', // public | internal | confidential | restricted
] as const;

export type RequiredTag = typeof REQUIRED_TAGS[number];

/**
 * Valid values for each required tag.
 * Resources with tags present but set to invalid values are also flagged.
 */
export const VALID_TAG_VALUES: Partial<Record<RequiredTag, readonly string[]>> = {
  environment: ['dev', 'staging', 'prod'],
  'data-classification': ['public', 'internal', 'confidential', 'restricted'],
};

/**
 * The outcome of validating a single resource's tags.
 */
export interface ComplianceResult {
  resourceId: string;
  resourceType: string;
  resourceName: string;
  compliant: boolean;
  missingTags: string[];
  invalidTags: Array<{ tag: string; value: string; allowed: string[] }>;
  presentTags: Record<string, string>;
}

/**
 * Validates that a resource carries all required tags with valid values.
 *
 * @param resource - Azure GenericResource from the ARM SDK
 * @returns ComplianceResult describing pass/fail and any violations
 */
export function validateResourceTags(resource: GenericResource): ComplianceResult {
  const resourceId = resource.id ?? 'unknown';
  const resourceType = resource.type ?? 'unknown';
  const resourceName = resource.name ?? 'unknown';
  const tags = resource.tags ?? {};

  const missingTags: string[] = [];
  const invalidTags: ComplianceResult['invalidTags'] = [];

  for (const requiredTag of REQUIRED_TAGS) {
    const value = tags[requiredTag];

    if (value === undefined || value === null || value.trim() === '') {
      missingTags.push(requiredTag);
      continue;
    }

    const allowedValues = VALID_TAG_VALUES[requiredTag];
    if (allowedValues && !allowedValues.includes(value.toLowerCase())) {
      invalidTags.push({
        tag: requiredTag,
        value,
        allowed: [...allowedValues],
      });
    }
  }

  return {
    resourceId,
    resourceType,
    resourceName,
    compliant: missingTags.length === 0 && invalidTags.length === 0,
    missingTags,
    invalidTags,
    presentTags: Object.fromEntries(
      Object.entries(tags).filter(([k]) =>
        REQUIRED_TAGS.includes(k as RequiredTag)
      )
    ),
  };
}

/**
 * Filters a list of compliance results to only non-compliant resources.
 */
export function getNonCompliant(results: ComplianceResult[]): ComplianceResult[] {
  return results.filter(r => !r.compliant);
}

/**
 * Calculates compliance rate as a percentage string.
 */
export function complianceRate(results: ComplianceResult[]): string {
  if (results.length === 0) return '0%';
  const rate = (results.filter(r => r.compliant).length / results.length) * 100;
  return rate.toFixed(1) + '%';
}
