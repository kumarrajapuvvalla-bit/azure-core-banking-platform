/**
 * compliance-checker — Azure Function (Timer Trigger)
 *
 * Runs on a schedule and validates that all Azure resources in the
 * subscription carry the mandatory FCA compliance tags:
 *
 *   - environment   (dev | staging | prod)
 *   - owner         (team or individual responsible)
 *   - cost-centre   (finance code for chargeback)
 *   - data-classification (public | internal | confidential | restricted)
 *
 * Non-compliant resources are logged and an alert summary is posted
 * to an Azure Monitor custom metric for dashboard visibility.
 *
 * FCA context: SYSC 8.1 requires regulated firms to maintain audit trails
 * of system ownership and data classification — these tags satisfy that.
 */

import { AzureFunction, Context } from '@azure/functions';
import { ResourceManagementClient } from '@azure/arm-resources';
import { DefaultAzureCredential } from '@azure/identity';
import { validateResourceTags, ComplianceResult, REQUIRED_TAGS } from './complianceRules';

const complianceChecker: AzureFunction = async (context: Context): Promise<void> => {
  const subscriptionId = process.env.AZURE_SUBSCRIPTION_ID;
  if (!subscriptionId) {
    context.log.error('AZURE_SUBSCRIPTION_ID environment variable is not set');
    throw new Error('Missing required environment variable: AZURE_SUBSCRIPTION_ID');
  }

  context.log.info('Starting FCA compliance tag check', {
    subscriptionId,
    requiredTags: REQUIRED_TAGS,
    timestamp: new Date().toISOString(),
  });

  const credential = new DefaultAzureCredential();
  const client = new ResourceManagementClient(credential, subscriptionId);

  const results: ComplianceResult[] = [];
  let totalResources = 0;

  // Paginate through all resources in the subscription
  for await (const resource of client.resources.list()) {
    totalResources++;
    const result = validateResourceTags(resource);
    results.push(result);
  }

  const compliant = results.filter(r => r.compliant);
  const nonCompliant = results.filter(r => !r.compliant);

  // Build summary report
  const summary = {
    totalResources,
    compliantCount: compliant.length,
    nonCompliantCount: nonCompliant.length,
    complianceRate: totalResources > 0
      ? ((compliant.length / totalResources) * 100).toFixed(1) + '%'
      : '0%',
    violations: nonCompliant.map(r => ({
      resourceId: r.resourceId,
      resourceType: r.resourceType,
      missingTags: r.missingTags,
      presentTags: r.presentTags,
    })),
  };

  context.log.info('FCA compliance check complete', summary);

  // Surface non-compliant resources as warnings for Azure Monitor
  if (nonCompliant.length > 0) {
    context.log.warn(
      `${nonCompliant.length} resource(s) are non-compliant with FCA tagging policy`,
      { violations: summary.violations }
    );
  }

  // Output binding writes summary to Azure Table Storage for audit trail
  context.bindings.complianceReport = JSON.stringify({
    runAt: new Date().toISOString(),
    ...summary,
  });
};

export default complianceChecker;
