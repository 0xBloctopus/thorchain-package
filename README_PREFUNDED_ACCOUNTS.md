# Prefunded Accounts Feature

The thorchain-package now supports prefunding accounts at genesis time through the `prefunded_accounts` configuration parameter.

## Configuration

Add `prefunded_accounts` to your chain configuration as a key-value object where:
- **Key**: Either a THORChain address (starting with "thor") or a mnemonic phrase
- **Value**: The amount to prefund (as a string, in base units)

### Example Configuration

```yaml
chains:
  - name: "thorchain-test"
    type: "thorchain"
    prefunded_accounts:
      "thor1abc123def456ghi789jkl012mno345pqr678stu": "1000000000000"  # Direct address
      "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about": "2000000000000"  # Mnemonic (will be converted)
```

## TypeScript Integration

### Generating Mnemonics and Addresses

To generate mnemonics and convert them to THORChain addresses in TypeScript, use the following approach:

```typescript
import { generateMnemonic } from '@cosmjs/crypto';
import { stringToPath } from '@cosmjs/crypto';
import { Secp256k1HdWallet } from '@cosmjs/amino';

// Generate a new mnemonic
const mnemonic = generateMnemonic();
console.log('Generated mnemonic:', mnemonic);

// Convert to THORChain address
const wallet = await Secp256k1HdWallet.fromMnemonic(mnemonic, {
  prefix: 'thor',
  hdPaths: [stringToPath("m/44'/931'/0'/0/0")]
});

const [{ address }] = await wallet.getAccounts();
console.log('THORChain address:', address);
```

### Required Dependencies

Install the required CosmJS packages:

```bash
npm install @cosmjs/crypto @cosmjs/amino
```

### Usage Options

You have two options for prefunding accounts:

1. **Use the address directly** (if you've already generated it):
   ```yaml
   prefunded_accounts:
     "thor1your_generated_address_here": "1000000000000"
   ```

2. **Use the mnemonic** (the package will convert it automatically):
   ```yaml
   prefunded_accounts:
     "your twelve word mnemonic phrase goes here like this example": "1000000000000"
   ```

## How It Works

1. The package processes the `prefunded_accounts` configuration
2. For addresses (starting with "thor"), they are used directly
3. For mnemonics, they are converted to addresses using the THORChain derivation path
4. All prefunded accounts are included in the genesis file's accounts and balances arrays
5. The accounts are funded with the specified amounts at network genesis

## Return Values

When using the package, the return object now includes:
- `prefunded_addresses`: Array of all prefunded addresses (including converted ones)
- `prefunded_mnemonics`: Array of mnemonics that were converted to addresses
