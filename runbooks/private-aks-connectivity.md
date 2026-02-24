# Runbook: Private AKS Connectivity Troubleshooting

**Related:** INC-006 — NSG quarterly hardening missed port 443

---

## Symptoms
All pipelines fail with:
```
Unable to connect to the server: dial tcp <ip>:443: i/o timeout
```

---

## Step 1 — Confirm it is a network issue (not auth)

From an agent VM:
```powershell
Test-NetConnection -ComputerName <aks-private-endpoint-ip> -Port 443
# TcpTestSucceeded: False → network block confirmed
# TLS error instead of timeout → network fine, check kubeconfig/auth
```

## Step 2 — Find the AKS private endpoint IP
```bash
az network private-endpoint show \
  --name pe-aks-corebanking-prod \
  --resource-group rg-corebanking-prod \
  --query "customDnsConfigs[0].ipAddresses[0]" -o tsv
```

## Step 3 — Check NSG rules
```bash
az network nsg rule list \
  --resource-group rg-corebanking-prod \
  --nsg-name nsg-devops-agents-prod \
  --query "[?direction=='Outbound']" -o table
```

Expected rule (this was missing in Month 12 incident):
```
Name: Allow-Agents-to-AKS-PrivateEndpoint-443
Direction: Outbound | Access: Allow | Protocol: TCP | Port: 443
```

## Step 4 — Fix via Terraform (preferred)
```bash
cd infrastructure/terraform/networking
terraform plan   # Should show the missing rule
terraform apply -target=azurerm_network_security_rule.agents_to_aks_api
```

## Step 5 — Verify
```bash
az aks get-credentials --resource-group rg-corebanking-prod --name aks-corebanking-prod
kubectl cluster-info   # Should return successfully
kubectl get nodes      # Should list all nodes Ready
```

## Prevention Checklist
- [ ] All NSG rules in Terraform — networking/nsg.tf
- [ ] Pre-flight kubectl cluster-info in all deployment pipelines
- [ ] Before quarterly network review, run terraform plan to baseline state
- [ ] After quarterly review, verify Test-NetConnection <aks-ip> -Port 443
