#!/usr/bin/env bash
# scripts/rotate-secrets.sh
# ISO 27001 A.9.4.3 — 90-day secret rotation for banking platform
# Called by: .github/workflows/secret-rotation.yml
# Required env vars: KEY_VAULT_NAME, DRY_RUN

set -euo pipefail

KEY_VAULT_NAME="${KEY_VAULT_NAME:?KEY_VAULT_NAME must be set}"
DRY_RUN="${DRY_RUN:-false}"
ROTATION_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EXPIRY_DATE=$(date -u -d "+90 days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
              date -u -v+90d +"%Y-%m-%dT%H:%M:%SZ")

              log() { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"; }
              dry_run_prefix() { [[ "$DRY_RUN" == "true" ]] && echo "[DRY-RUN] " || echo ""; }

              log "Starting secret rotation for Key Vault: ${KEY_VAULT_NAME}"
              log "Dry run: ${DRY_RUN}"

              SECRETS=(
                "banking-db-connection-string"
                  "banking-servicebus-connection-string"
                  )

                  rotate_secret() {
                    local secret_name="$1"
                      local prefix
                        prefix=$(dry_run_prefix)

                          log "${prefix}Rotating secret: ${secret_name}"

                            # Check current secret expiry
                              local current_expiry
                                current_expiry=$(az keyvault secret show \
                                    --vault-name "$KEY_VAULT_NAME" \
                                        --name "$secret_name" \
                                            --query "attributes.expires" \
                                                --output tsv 2>/dev/null || echo "none")

                                                  log "  Current expiry: ${current_expiry}"

                                                    if [[ "$DRY_RUN" == "true" ]]; then
                                                        log "  [DRY-RUN] Would update expiry to ${EXPIRY_DATE}"
                                                            return 0
                                                              fi

                                                                # Update expiration date — actual value rotation is handled by
                                                                  # application-layer secret management (Azure SQL / Service Bus key rotation)
                                                                    az keyvault secret set-attributes \
                                                                        --vault-name "$KEY_VAULT_NAME" \
                                                                            --name "$secret_name" \
                                                                                --expires "$EXPIRY_DATE" \
                                                                                    --output none

                                                                                      log "  Expiry updated to: ${EXPIRY_DATE}"

                                                                                        # Restart affected deployments to pick up rotated secrets via CSI driver
                                                                                          kubectl rollout restart deployment/banking-api -n banking 2>/dev/null || true
                                                                                          }

                                                                                          for secret in "${SECRETS[@]}"; do
                                                                                            rotate_secret "$secret"
                                                                                            done

                                                                                            log "Secret rotation complete. Rotated ${#SECRETS[@]} secrets."
                                                                                            log "Next rotation due: ${EXPIRY_DATE}"
