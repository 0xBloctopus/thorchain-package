#!/bin/bash

GENESIS_FILE="/tmp/genesis.json"
NEW_BALANCES_FILE="/tmp/new_balances.json"
TEMP_FILE="/tmp/genesis_temp.json"

jq --slurpfile new_balances "$NEW_BALANCES_FILE" '
  ($new_balances[0] | map(.coins[].denom) | unique) as $balance_denoms |
  
  .app_state.bank.balances = $new_balances[0] |
  
  .app_state.bank.supply = (.app_state.bank.supply | map(select(.denom as $d | $balance_denoms | contains([$d])))) |
  
  .app_state.bank.supply |= map(
    .denom as $supply_denom |
    .amount = (
      $new_balances[0] 
      | map(.coins[] | select(.denom == $supply_denom) | .amount | tonumber) 
      | add 
      | tostring
    )
  )
' "$GENESIS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$GENESIS_FILE"

echo "Replaced balances and filtered supply to match"
