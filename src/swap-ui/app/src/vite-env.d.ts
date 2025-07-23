
interface ImportMetaEnv {
  readonly VITE_NODE_URL: string
  readonly VITE_NODE_RPC: string
  readonly VITE_PREFUNDED_MNEMONIC: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
