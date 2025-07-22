import React, { useState, useEffect } from 'react'
import axios from 'axios'
import './SwapInterface.css'

interface SwapQuote {
  sellAmount: string
  buyAmount: string
  fees: {
    total: string
  }
  route: any[]
}

const SwapInterface: React.FC = () => {
  const [sellAmount, setSellAmount] = useState('')
  const [buyAmount, setBuyAmount] = useState('')
  const [quote, setQuote] = useState<SwapQuote | null>(null)
  const [swapping, setSwapping] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [walletConnected, setWalletConnected] = useState(false)

  const buyAsset = 'THOR.RUJI'
  const prefundedMnemonic = 'maple forest blouse coffee explain category grass punch carry raise trust weekend'

  const nodeUrl = import.meta.env.VITE_NODE_URL || window.location.origin + '/api'

  useEffect(() => {
    if (sellAmount && parseFloat(sellAmount) > 0) {
      getQuote()
    } else {
      setBuyAmount('')
      setQuote(null)
    }
  }, [sellAmount])

  const getQuote = async () => {
    if (!sellAmount || parseFloat(sellAmount) <= 0) return

    setError('')

    try {
      const poolsResponse = await axios.get(`${nodeUrl}/thorchain/pools`)
      const pools = poolsResponse.data
      
      const rujiPool = pools.find((pool: any) => pool.asset === 'THOR.RUJI')
      
      if (!rujiPool) {
        throw new Error('RUJI pool not found')
      }

      const runeDepth = parseInt(rujiPool.balance_rune)
      const assetDepth = parseInt(rujiPool.balance_asset)
      const sellAmountBase = parseFloat(sellAmount) * 1e8
      
      const outputAmount = (sellAmountBase * assetDepth) / (runeDepth + sellAmountBase)
      
      const quoteData = {
        sellAmount: sellAmountBase.toString(),
        buyAmount: Math.floor(outputAmount).toString(),
        fees: {
          total: '2000000' // 0.02 RUNE fee estimate
        },
        route: []
      }
      
      setQuote(quoteData)
      setBuyAmount((outputAmount / 1e8).toFixed(6))
    } catch (err: any) {
      setError('Failed to get quote: ' + (err.response?.data?.message || err.message))
      setBuyAmount('')
      setQuote(null)
    } finally {
    }
  }

  const executeSwap = async () => {
    if (!sellAmount || parseFloat(sellAmount) <= 0) return

    setSwapping(true)
    setError('')
    setSuccess('')

    try {
      const swapAmount = Math.floor(parseFloat(sellAmount) * 1e8).toString()
      const memo = `=:${buyAsset}:thor1k0ypgljd8cxf5ymvm0ekt3md29mlzu2zu7khyj`
      
      console.log('Creating signed transaction with prefunded mnemonic...')
      
      const msgDeposit = {
        "@type": "/types.MsgDeposit",
        coins: [{
          asset: "THOR.RUNE",
          amount: swapAmount
        }],
        memo: memo,
        signer: "thor1k0ypgljd8cxf5ymvm0ekt3md29mlzu2zu7khyj"
      }

      const txBody = {
        messages: [msgDeposit],
        memo: "",
        timeout_height: "0",
        extension_options: [],
        non_critical_extension_options: []
      }

      const authInfo = {
        signer_infos: [{
          public_key: null,
          mode_info: {
            single: {
              mode: "SIGN_MODE_DIRECT"
            }
          },
          sequence: "0"
        }],
        fee: {
          amount: [],
          gas_limit: "4000000000",
          payer: "",
          granter: ""
        }
      }

      const tx = {
        body: txBody,
        auth_info: authInfo,
        signatures: [""] // Would need proper signature here
      }

      console.log('Broadcasting transaction:', tx)

      const response = await axios.post(`${nodeUrl}/cosmos/tx/v1beta1/txs`, {
        tx_bytes: btoa(JSON.stringify(tx)), // Base64 encode the transaction
        mode: "BROADCAST_MODE_SYNC"
      })

      if (response.data && response.data.tx_response) {
        if (response.data.tx_response.code === 0) {
          setSuccess(`Swap successful! Transaction hash: ${response.data.tx_response.txhash}. Swapped ${sellAmount} RUNE for ${buyAmount} RUJI.`)
        } else {
          throw new Error(`Transaction failed: ${response.data.tx_response.raw_log}`)
        }
        setSellAmount('')
        setBuyAmount('')
        setQuote(null)
      } else {
        throw new Error('Invalid response from transaction broadcast')
      }
    } catch (err: any) {
      console.error('Swap error:', err)
      if (err.response?.status === 400 && err.response?.data?.message?.includes('signature')) {
        setError(`Transaction signing failed. Need to implement proper signature with mnemonic: "${prefundedMnemonic.split(' ').slice(0, 3).join(' ')}..."`)
      } else {
        setError(`Swap failed: ${err.message}. Using real pool data (${sellAmount} RUNE = ${buyAmount} RUJI) but transaction signing needs implementation.`)
      }
    } finally {
      setSwapping(false)
    }
  }

  const connectWallet = async () => {
    try {
      setSuccess('Wallet connection simulated - using prefunded account for swaps')
      setWalletConnected(true)
    } catch (err: any) {
      setError('Failed to connect wallet: ' + err.message)
    }
  }

  return (
    <div className="swap-container">
      <div className="swap-card">
        <div className="swap-header">
          <h2 className="swap-title">Swap</h2>
        </div>

        <div className="swap-form">
          {/* Sell Section */}
          <div className="swap-section">
            <div className="swap-section-header">
              <span className="swap-label">From</span>
              <span className="swap-balance">Balance: 0</span>
            </div>
            <div className="swap-input-container">
              <input
                type="number"
                value={sellAmount}
                onChange={(e) => setSellAmount(e.target.value)}
                placeholder="0"
                className="swap-input"
              />
              <div className="asset-selector">
                <div className="asset-info">
                  <div className="asset-icon">⚡</div>
                  <div className="asset-details">
                    <div className="asset-symbol">RUNE</div>
                    <div className="asset-name">NATIVE</div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* Swap Arrow */}
          <div className="swap-arrow-container">
            <button className="swap-arrow">
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                <path d="M8 1L8 15M8 15L15 8M8 15L1 8" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
            </button>
          </div>

          {/* Buy Section */}
          <div className="swap-section">
            <div className="swap-section-header">
              <span className="swap-label">To</span>
              <span className="swap-balance">Balance: 0</span>
            </div>
            <div className="swap-input-container">
              <input
                type="number"
                value={buyAmount}
                onChange={(e) => setBuyAmount(e.target.value)}
                placeholder="0"
                className="swap-input"
              />
              <div className="asset-selector">
                <div className="asset-info">
                  <div className="asset-icon">🔥</div>
                  <div className="asset-details">
                    <div className="asset-symbol">RUJI</div>
                    <div className="asset-name">THOR</div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* Quote Info */}
          {quote && (
            <div className="quote-info">
              <div className="quote-row">
                <span>1 RUNE = {(parseFloat(buyAmount) / parseFloat(sellAmount)).toFixed(6)} RUJI</span>
                <span>Fees: {(parseInt(quote.fees.total) / 1e8).toFixed(8)} RUNE</span>
              </div>
            </div>
          )}

          {/* Error/Success Messages */}
          {error && (
            <div className="message error-message">
              {error}
            </div>
          )}
          {success && (
            <div className="message success-message">
              {success}
            </div>
          )}

          {/* Action Buttons */}
          <div className="swap-actions">
            {walletConnected ? (
              <button
                onClick={executeSwap}
                disabled={!sellAmount || parseFloat(sellAmount) <= 0 || swapping}
                className="swap-button primary"
              >
                {swapping ? 'Swapping...' : 'Swap'}
              </button>
            ) : (
              <button
                onClick={connectWallet}
                className="swap-button primary"
              >
                Connect Wallet
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

export default SwapInterface
