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

**Method 1: Generate from entropy (more control)**
```typescript
import { Random, Bip39, stringToPath } from '@cosmjs/crypto';
import { Secp256k1HdWallet } from '@cosmjs/amino';

// Generate entropy and convert to mnemonic
const entropy = Random.getBytes(32);
const mnemonic = Bip39.encode(entropy).toString();
console.log('Generated mnemonic:', mnemonic);

// Convert to THORChain address
const wallet = await Secp256k1HdWallet.fromMnemonic(mnemonic, {
  prefix: 'thor',
  hdPaths: [stringToPath("m/44'/931'/0'/0/0")]
});

const [{ address }] = await wallet.getAccounts();
console.log('THORChain address:', address);
```

**Method 2: Direct generation (simpler)**
```typescript
import { stringToPath } from '@cosmjs/crypto';
import { Secp256k1HdWallet } from '@cosmjs/amino';

// Generate wallet directly with 12-word mnemonic
const wallet = await Secp256k1HdWallet.generate(12, {
  prefix: 'thor',
  hdPaths: [stringToPath("m/44'/931'/0'/0/0")]
});

const mnemonic = wallet.mnemonic;
const [{ address }] = await wallet.getAccounts();
console.log('Generated mnemonic:', mnemonic);
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

## Go Address Derivation

### Method 1: Using THORNode CLI (Recommended)

The thorchain-package uses the THORNode CLI for reliable address derivation:

```go
package main

import (
    "encoding/json"
    "fmt"
    "os/exec"
    "strings"
)

type KeyOutput struct {
    Address  string `json:"address"`
    Mnemonic string `json:"mnemonic"`
}

func generateThorchainAddress(mnemonic string) (string, error) {
    // Use thornode CLI to recover address from mnemonic
    cmd := exec.Command("sh", "-c", 
        fmt.Sprintf("echo '%s' | thornode keys add temp --keyring-backend test --recover --output json", mnemonic))
    
    output, err := cmd.Output()
    if err != nil {
        return "", fmt.Errorf("failed to generate address: %v", err)
    }
    
    var keyOutput KeyOutput
    if err := json.Unmarshal(output, &keyOutput); err != nil {
        return "", fmt.Errorf("failed to parse output: %v", err)
    }
    
    // Clean up the temporary key
    exec.Command("thornode", "keys", "delete", "temp", "--keyring-backend", "test", "--yes").Run()
    
    return keyOutput.Address, nil
}

func main() {
    mnemonic := "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    address, err := generateThorchainAddress(mnemonic)
    if err != nil {
        fmt.Printf("Error: %v\n", err)
        return
    }
    fmt.Printf("THORChain address: %s\n", address)
}
```

### Method 2: Using Cosmos SDK (Alternative)

For applications that prefer using the Cosmos SDK directly:

```go
package main

import (
    "fmt"
    
    "github.com/cosmos/cosmos-sdk/crypto/hd"
    "github.com/cosmos/cosmos-sdk/crypto/keys/secp256k1"
    "github.com/cosmos/cosmos-sdk/types/bech32"
    "github.com/cosmos/go-bip39"
)

func generateThorchainAddressSDK(mnemonic string) (string, error) {
    // Generate seed from mnemonic
    seed, err := bip39.NewSeedWithErrorChecking(mnemonic, "")
    if err != nil {
        return "", fmt.Errorf("invalid mnemonic: %v", err)
    }
    
    // Derive private key using THORChain's derivation path (m/44'/931'/0'/0/0)
    derivedPriv, err := hd.Secp256k1.Derive()(seed, "m/44'/931'/0'/0/0", "")
    if err != nil {
        return "", fmt.Errorf("failed to derive private key: %v", err)
    }
    
    // Generate secp256k1 private key
    privKey := &secp256k1.PrivKey{Key: derivedPriv}
    
    // Get public key and convert to address
    pubKey := privKey.PubKey()
    addr := pubKey.Address()
    
    // Encode with THORChain's bech32 prefix "thor"
    bech32Addr, err := bech32.ConvertAndEncode("thor", addr)
    if err != nil {
        return "", fmt.Errorf("failed to encode address: %v", err)
    }
    
    return bech32Addr, nil
}

func main() {
    mnemonic := "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    address, err := generateThorchainAddressSDK(mnemonic)
    if err != nil {
        fmt.Printf("Error: %v\n", err)
        return
    }
    fmt.Printf("THORChain address: %s\n", address)
}
```

### Required Go Dependencies

For the Cosmos SDK approach, add these dependencies to your `go.mod`:

```go
require (
    github.com/cosmos/cosmos-sdk v0.47.0
    github.com/cosmos/go-bip39 v1.0.0
)
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
